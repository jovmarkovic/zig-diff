# zdif

A simple command-line diff tool written in [Zig](https://ziglang.org/) that compares two text files using Myers' Diff algorithm, outputs their differences via backtracking in a format similar to the GNU `diff` utility.

---

## Features

- Compare two text files line-by-line.
- Supports ignoring lines starting with a custom marker (e.g., comments).
- Optionally skip empty or whitespace-only lines.
- Outputs differences using standard diff notation - (`c`, `a`, `d`).
- Prints clear, human-readable diff output.
- Minimal dependencies — just Zig standard library.

---

## Usage

Build the project using Zig:

```sh
zig build
````

Or run directly without building:

```sh
zig run src/main.zig -- [options] <file1> <file2>
```

### Options

* `--normal`
  GNU normal diff style. (DEFAULT)

* `-m "#"`, `--marker '//'`
  Remove lines starting with specific marker - (double) quotes optional.

* `-s`, `--skip-empty`
  Skip empty or whitespace-only lines from comparison.

* `-u`, `--unified`
  GNU unified diff style (default 3) lines of context with hunk merging. - WIP

* `-p`, `--print`
  Prints the output of two files with optional processing and skips comparison.

* `-h`, `--help`
  Show usage information.

---

### Examples - run with out compiling

```sh
# Compare two files normally
zig run src/main.zig -- testfile1 testfile2

# Ignore lines starting with "#" and compare
zig run src/main.zig -- -m "#" testfile1 testfile2

# Ignore empty lines and lines starting with '//', just print
zig run src/main.zig -- -m '//' -s -p testfile1 testfile2
```

---

## Development

* Requires [Zig 0.14+](https://ziglang.org/download/)
* Uses Zig standard library only.
* Source files are in the `src/` directory.
* Build script: `build.zig`

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

---

## Contributing

Feel free to submit issues or pull requests.
Bug reports and feature requests are welcome!

---

## Contact

For questions or help, please open an issue or contact the author.

```
miagi@vivaldi.net
```

