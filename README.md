# Subtitle Compare and Shift Workflow (SCSW)

This utility is designed to resync `.srt` files using an existing subtitle/audio reference track that is already aligned in the compare file.

I developed this workflow to manage subtitles for the K-dramas my wife watches, in a practical and repeatable way.

This project helps you align `.srt` subtitles with `.ass` subtitles.

## 0) Extract Subtitles from MKV Files

Use `scsw_extract.sh` to extract every subtitle stream from each `.mkv` file in a target folder.

Default output (`target_folder/out`):

```bash
./scsw_extract.sh /path/to/mkv_folder
```

Custom output folder:

```bash
./scsw_extract.sh /path/to/mkv_folder /path/to/output_folder
```

What this does:
- Scans all `.mkv` files in the target folder.
- Extracts all subtitle streams for each file.
- Writes one output file per subtitle stream.

## 1) Prepare a Working Folder

Create a folder that contains matching subtitle pairs.

Rules:
- Put both subtitle files in the same folder.
- The base file name must match (text before the first dot).
- Keep the original extensions/suffixes.

Example files in one folder:
- `My Show - 01x01.it.srt`
- `My Show - 01x01.track2.eng.ass`

In this case, the matching base file name is `My Show - 01x01`.

## 2) Generate Compare Files

Run `scsw_compare.sh` from inside the working folder.

Default extensions (`srt` and `ass`):

```bash
../scsw_compare.sh . 30
```

Custom extensions:

```bash
../scsw_compare.sh . 30 it.srt track2.eng.ass
```

Supported combinations include:
- ass -> ass
- srt -> srt
- srt -> ass

What this does:
- Creates an `out/` folder inside your current folder.
- Writes one `*.compare.txt` file for each matched pair.

## 3) Manually Edit Compare Files

Open files in `out/*.compare.txt` and manually leave only one line from each subtitle file (with the same content in different languages).

The `scsw_shift.sh` script reads the first timestamp line under each section:
- `[...srt]`
- `[...ass]`

Those two timestamps are used to compute the shift.

## 4) Apply the Shift

Run shift on the edited compare files:

```bash
../scsw_shift.sh out/*.compare.txt
```

If your source subtitle extension is custom, pass it with `-f`:

```bash
../scsw_shift.sh -f it.srt out/*.compare.txt
```

You can choose both source and reference section extensions:

```bash
../scsw_shift.sh -f it.srt -t track2.eng.ass out/*.compare.txt
```

Supported combinations include:
- ass -> ass
- srt -> srt
- srt -> ass

What this does:
- Searches source subtitle files in your current folder.
- Creates/updates shifted subtitle files in `./out`.
- Copies compare files into `./out`.

## Requirements

- Bash shell (Linux/macOS/WSL).
- `ffmpeg` and `ffprobe` available in `PATH` (required for `scsw_extract.sh`).
