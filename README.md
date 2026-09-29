# extract_img

extract data:url images from text

## Overview

A small CLI to extract embedded data URL images (data:image/*;base64,...) from text files, Markdown, or HTML.

## Install/use

Run the script directly from this folder or move into your PATH

```bash
./extract_img --help
```

### Common usage

From piped input:

```bash
cat doc.md | ./extract_img
```

From one file:

```bash
./extract_img -i doc.md
```

From multiple files (glob):

```bash
./extract_img -i "**/*.md" -o extracted_images
```

Dry run (preview output filenames, write nothing):

```bash
./extract_img -i doc.md --dry-run
```

### Options

```text
  -i PATH               Input file or glob (can be passed multiple times)
  -o DIR                Output directory (default: current directory)
  --dry-run             Show what would be written without creating files
  --any-data            Extract all base64 data URLs, not only image/*
  --[no-]detect-formats Derive extension from MIME type (default: true)
  --[no-]overwrite      Overwrite existing files (default: false)
  --[no-]print-paths    Print extracted file paths to stdout (default: true)
  -h, --help            Show help
```

Notes

- The tool looks for base64 data URLs anywhere in the input. It will match Markdown and HTML image usages because both embed data URLs directly.
- Default naming is incremental: image_1.png, image_2.jpg, ...
