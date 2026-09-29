# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "tmpdir"
require "fileutils"
require "pty"
require "English"

class ExtractImgTest < Minitest::Test
  INPUT_ALL = <<~TEXT
    Image PNG: data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7ZxYQAAAAASUVORK5CYII=
    Image SVG: data:image/svg+xml;base64,PHN2Zy8+
    Text DATA: data:text/plain;base64,aGVsbG8=
  TEXT

  INPUT_PNG_ONLY = <<~TEXT
    Only PNG: data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7ZxYQAAAAASUVORK5CYII=
  TEXT

  def setup
    @root = File.expand_path("..", __dir__)
    @script = File.join(@root, "extract_img")
    @tmpdir = Dir.mktmpdir("extract_img_test_")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_help_prints_usage_and_exits_zero
    result = run_cmd("--help")

    assert_equal 0, result[:status]
    assert_includes result[:stdout], "Usage: extract_img"
  end

  def test_invalid_option_exits_two
    result = run_cmd("--not-a-real-option")

    assert_equal 2, result[:status]
    assert_includes result[:stderr], "invalid option"
  end

  def test_stdin_default_extracts_only_images
    out_dir = mkpath("stdin/out")

    result = run_cmd("-o", out_dir, stdin_data: INPUT_ALL)

    assert_equal 0, result[:status]
    assert File.exist?(File.join(out_dir, "image_1.png"))
    assert File.exist?(File.join(out_dir, "image_2.svg"))
    refute File.exist?(File.join(out_dir, "image_3.bin"))
    assert_includes result[:stdout], File.join(out_dir, "image_1.png")
    assert_includes result[:stdout], File.join(out_dir, "image_2.svg")
    assert_includes result[:stderr], "Done. 2 image(s) extracted"
  end

  def test_any_data_extracts_non_image_data_urls
    input = write_file("any_data/input.txt", INPUT_ALL)
    out_dir = mkpath("any_data/out")

    result = run_cmd("-i", input, "-o", out_dir, "--any-data")

    assert_equal 0, result[:status]
    assert File.exist?(File.join(out_dir, "image_3.plain"))
    assert_includes result[:stderr], "Done. 3 image(s) extracted"
  end

  def test_no_detect_formats_uses_sanitized_subtype
    input = write_file("no_detect/input.txt", INPUT_ALL)
    out_dir = mkpath("no_detect/out")

    result = run_cmd("-i", input, "-o", out_dir, "--no-detect-formats")

    assert_equal 0, result[:status]
    assert File.exist?(File.join(out_dir, "image_1.png"))
    assert File.exist?(File.join(out_dir, "image_2.svgxml"))
    refute File.exist?(File.join(out_dir, "image_2.svg"))
  end

  def test_detect_formats_maps_svg_plus_xml_to_svg
    input = write_file("detect/input.txt", INPUT_ALL)
    out_dir = mkpath("detect/out")

    result = run_cmd("-i", input, "-o", out_dir, "--detect-formats")

    assert_equal 0, result[:status]
    assert File.exist?(File.join(out_dir, "image_2.svg"))
  end

  def test_dry_run_does_not_write_files
    input = write_file("dry/input.txt", INPUT_ALL)
    out_dir = mkpath("dry/out")

    result = run_cmd("-i", input, "-o", out_dir, "--dry-run")

    assert_equal 0, result[:status]
    assert_includes result[:stdout], "DRY-RUN: would write"
    refute File.exist?(File.join(out_dir, "image_1.png"))
    assert_includes result[:stderr], "Dry run complete. 2 image(s) would be extracted."
  end

  def test_no_print_paths_suppresses_stdout
    input = write_file("no_print/input.txt", INPUT_ALL)
    out_dir = mkpath("no_print/out")

    result = run_cmd("-i", input, "-o", out_dir, "--no-print-paths")

    assert_equal 0, result[:status]
    assert_equal "", result[:stdout]
  end

  def test_default_overwrite_false_creates_suffixed_file
    input = write_file("overwrite_default/input.txt", INPUT_PNG_ONLY)
    out_dir = mkpath("overwrite_default/out")
    File.write(File.join(out_dir, "image_1.png"), "seed")

    result = run_cmd("-i", input, "-o", out_dir)

    assert_equal 0, result[:status]
    assert File.exist?(File.join(out_dir, "image_1_1.png"))
    assert_includes result[:stdout], File.join(out_dir, "image_1_1.png")
  end

  def test_overwrite_reuses_original_filename
    input = write_file("overwrite/input.txt", INPUT_PNG_ONLY)
    out_dir = mkpath("overwrite/out")
    File.write(File.join(out_dir, "image_1.png"), "seed")

    result = run_cmd("-i", input, "-o", out_dir, "--overwrite")

    assert_equal 0, result[:status]
    assert File.exist?(File.join(out_dir, "image_1.png"))
    refute File.exist?(File.join(out_dir, "image_1_1.png"))
    assert_includes result[:stdout], File.join(out_dir, "image_1.png")
  end

  def test_multiple_input_flags_and_glob
    src_dir = mkpath("glob/src")
    out_dir = mkpath("glob/out")
    write_file("glob/src/a.md", INPUT_PNG_ONLY)
    write_file("glob/src/b.md", INPUT_PNG_ONLY)
    write_file("glob/src/c.txt", INPUT_PNG_ONLY)

    glob = File.join(src_dir, "*.md")
    txt = File.join(src_dir, "c.txt")

    result = run_cmd("-i", glob, "-i", txt, "-o", out_dir)

    assert_equal 0, result[:status]
    count = Dir.glob(File.join(out_dir, "*")).count { |p| File.file?(p) }
    assert_equal 3, count
  end

  def test_without_input_and_without_piped_stdin_exits_two
    result = run_with_tty

    assert_equal 2, result[:status]
    assert_includes result[:stderr], "No inputs and STDIN is a TTY"
  end

  private

  def mkpath(rel)
    path = File.join(@tmpdir, rel)
    FileUtils.mkdir_p(path)
    path
  end

  def write_file(rel, content)
    path = File.join(@tmpdir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def run_cmd(*args, stdin_data: nil)
    cmd = ["ruby", @script, *args]
    stdout, stderr, status = Open3.capture3(*cmd, stdin_data: stdin_data.to_s)

    {
      stdout: stdout,
      stderr: stderr,
      status: status.exitstatus
    }
  end

  def run_with_tty
    cmd = ["ruby", @script]
    stdout = +""
    status_code = nil

    begin
      PTY.spawn(*cmd) do |read_io, write_io, _pid|
        write_io.close
        begin
          loop do
            stdout << read_io.readpartial(1024)
          end
        rescue EOFError, Errno::EIO
          # End of PTY stream.
        end
      end
      status_code = $CHILD_STATUS&.exitstatus
    rescue PTY::ChildExited => e
      status_code = e.status.exitstatus if e.respond_to?(:status) && e.status
    end

    status_code = -1 if status_code.nil?

    # OptionParser and warnings can emit to stderr; PTY merges output streams.
    {
      stdout: stdout,
      stderr: stdout,
      status: status_code
    }
  end
end
