# photodetect2

Determine if an the contents of an image are photographic or not.

This is a re-implementation of Julio Barba's screen content detection algorithm used in the [SVT-AV1-PSY](https://github.com/psy-ex/svt-av1-psy) project. A reference implementation can be found [here](https://gist.github.com/juliobbv-p/eabe5b048f956db5329951eaa5724d53).

This implementation is written in pure Zig, and decodes PAM images to compute screen content determination.

## Usage

```bash
Usage: sccdetect <input.pam>
```
The output will be a member of the `ScreenContentClass` enum, which is printed to the terminal when using this tool's CLI.

Example inputs are provided in the `examples/` directory in this repository.

## Output

- `OUT_SC_PHOTO`: Likely photographic content
- `OUT_SC_BASIC`: Basic screen content detected
- `OUT_SC_HIVAR`: Screen content + high variance
- `OUT_SC_MED`: Stronger screen content indication (relaxed variance requirement)
- `OUT_SC_HIGH`: Strongest screen content indication

More information is provided in the annotated [C reference implementation](https://gist.github.com/juliobbv-p/eabe5b048f956db5329951eaa5724d53).
