# Noka Console Reference

Complete specification of the Noka virtual machine: display, memory, and discs.

For the language that runs on it, see [LANGUAGE.md](LANGUAGE.md).

## Design Principles

- **The limits are the spec:** display size, RAM map, and disc capacity are published, stable, and part of the console's identity. Implementations fit inside them, not the other way around.
- **One grid:** text cell, tile, and sprite are all 8×8. There is no second unit of layout.
- **Mobile-first and portrait:** the screen is taller than it is wide, and 24 columns wide, because thumbs type on phones. See LANGUAGE.md's design principles.
- **One palette:** DHARM32 on the 15-bit ladder is the console's look. It is not configurable and carts cannot ship their own (for now).
- **Discs are self-contained:** one binary container (.noka) holds a cart's code, art, and sound. It is created, edited, and shared inside the Noka app.
- **Budgets, not walls:** the disc is a hard limit because a medium has a size. Everything else that constrains the author is advisory.
- **Reserve early:** address ranges are cheap now and impossible to move once carts exist.

## Display

| Property | Value |
|----------|-------|
| Resolution | 192 × 224 |
| Aspect | 6:7 (0.857), portrait |
| Cell size | 8 × 8 |
| Grid | 24 × 28 cells |
| Colors | 32, palette-indexed |
| Color depth | 15-bit (RGB555), 32768 possible |
| Storage | 8 bpp (one byte per pixel) |

The width is not arbitrary: **192 = 24 columns × 8 px**. LANGUAGE.md targets a narrow single-column screen, and the display is sized to it rather than the reverse.

192 is `3 × 64`, so a row stride is two shifts and an add rather than a multiply, and the framebuffer is exactly 42 KiB.

The text cell, the tile, and the sprite are the same 8×8 square. A screen is 24×28 of them whichever way you're using it.

### Color

Color lives at two layers, and they have different widths.

**A pixel is a palette index, one byte.** Only indices `0`-`31` are valid; `32`-`255` are reserved and their behavior is undefined. Storing 8 bits for a 5-bit index wastes three bits per pixel, deliberately: it keeps every pixel byte-aligned, makes VRAM addressing a plain `y * 192 + x`, and leaves room to widen the palette later without changing the cart format or the memory map.

**A palette entry is a `u16` in RGB5551 format**, little-endian, at `PALETTE`:

```
 15  14        10   9         5   4         0
┌───┬─────────────┬─────────────┬─────────────┐
│ A │   R (5)     │   G (5)     │   B (5)     │
└───┴─────────────┴─────────────┴─────────────┘
```

Five bits per channel is **15-bit color** (the SNES color space). There is exactly one palette, DHARM32, and it already sits on that ladder, so nothing needs quantizing at runtime. The format is chosen for compactness and for the spare bit in bit 15.

The whole palette is 32 × 2 = 64 bytes. It is loaded into `PALETTE` at boot and may be written by a running program. Palette effects are the cheapest animation on this kind of machine, but no cart supplies its own, and there is no import path (yet).

Tiles and sprites may use **all 32 colors**. Noka has no sub-palettes and no per-cell color limit; the 16-bit consoles this palette evokes were more restrictive here, and Noka deliberately is not.

### Transparency

Bit 15 of a palette entry marks that index **transparent**. When blitting sprites or tiles, pixels whose index is transparent are skipped rather than written. In the framebuffer a transparent index still displays its color, but it is the backdrop that shows through.

By convention **index 0 is transparent**, which is what art tools and artists expect. But the mechanism is the palette bit, not the index, so a program may mark any set of indices transparent and change them at runtime. Palette-flag tricks such as flashing, fading, ghosting, recolors, etc cost nothing and were how the real hardware did the same effects.

Implementations should precompute a `u32` mask of transparent indices so a blit tests `(mask >> idx) & 1`.

There is no per-pixel alpha and no blending. Blending two palette indices does not produce a palette index, so an indexed framebuffer cannot express it. Transparency is binary.

### The Palette

[DHARM32](https://lospec.com/palette-list/dharm32-15-bit) by DHARM. 32 colors, designed on the 15-bit ladder for an SNES/Genesis feel. This is the console's palette. There is no other (for now).

```
midnight  00 080810   
plum      01 292139   
slate     02 636b7b
fog       03 8c9cb5
ice       04 c6cede
paper     05 f7fff7
cyan      06 52e7e7   
azure     07 1094de
cobalt    08 184a9c
indigo    09 313963
spruce    10 102931
pine      11 105239
clover    12 219439
grass     13 52c64a
lime      14 84ef39
lemon     15 f7ef5a
amber     16 f7a518
clay      17 de8442
flame     18 f77321
peach     19 f7bd94
melon     20 efa573
caramel   21 ce8c5a
copper    22 b56b42
umber     23 7b3921
oxblood   24 311821
brick     25 8c1821
scarlet   26 e71839
coral     27 f74a6b
blush     28 f7848c
berry     29 942963
grape     30 522152
mauve     31 6b4a6b
```

Every channel value above is on the 32-step ladder `00 08 10 18 21 29 31 39 42 4a 52 5a 63 6b 73 7b 84 8c 94 9c a5 ad b5 bd c6 ce d6 de e7 ef f7 ff`, so each color survives the round trip through RGB555 exactly.

Index 0 (`080810`) carries the transparent flag by default.

## Memory Map

Total console RAM is **512 KiB**.

| Address | Size | Region | Program access |
|---------|------|--------|----------------|
| `0x00000` | 64 KiB | `DISC`: loaded cart image, verbatim | R |
| `0x10000` | 64 KiB | `CODE`: bytecode arena | - |
| `0x20000` | 64 KiB | `CONST`: constant pool, 4096 × 16 B | - |
| `0x30000` | 48 KiB | `VRAM`: 192×224 @ 8bpp (42 KiB used) | R/W |
| `0x3C000` | 16 KiB | `SPRITES`: 128×128 @ 8bpp, 256 sprites | R/W |
| `0x40000` | 8 KiB | `MAP`: 128×64 tiles, 1 byte each | R/W |
| `0x42000` | 16 KiB | `SFX` | R/W |
| `0x46000` | 4 KiB | `PALETTE` (64 B) + IO registers | R/W |
| `0x47000` | 4 KiB | `STACK`: value stack, 256 × 16 B | - |
| `0x48000` | 16 KiB | `FRAMES`: call frames | - |
| `0x4C000` | 128 KiB | `HEAP`: strings, arrays, objects | - |
| `0x6C000` | 80 KiB | *reserved* | - |
| `0x80000` | | end | |

Two properties worth preserving as this grows:

**The writable region is contiguous.** `VRAM` through `PALETTE` is one unbroken span, `0x30000`-`0x46FFF` (92 KiB). Any future `peek`/`poke` is a single bounds check, and programs can copy between graphics regions freely.

**`CODE` and `CONST` are invisible to the program.** Self-modifying bytecode is not a feature. They appear here for accounting only.

## Discs

A disc is a **binary container of at most 65536 bytes, header included.**

The 48-byte header counts against the limit, so a payload tops out at **65488 bytes**. That keeps `DISC` a clean 64 KiB region that holds a whole disc image with nothing hanging off the end.

Size is measured **uncompressed**. Compression is a storage detail the author never reasons about: a disc that fits, fits, regardless of how well it happens to squeeze. Budgeting against compressed size would mean adding a comment could shrink a cart and removing one could break it, which makes the budget unpredictable in exactly the way the token gauge is designed not to be.

How the remaining space divides between source and assets is the author's choice.

Disc files end in `.noka`!

### Header

48 bytes, uncompressed, at the start of the file.

| Offset | Size | Field |
|--------|------|-------|
| `0x00` | 4 | Magic: `NOKA` |
| `0x04` | 1 | Format version, major |
| `0x05` | 1 | Format version, minor |
| `0x06` | 1 | Format version, patch |
| `0x07` | 1 | Flags: bit 0 = payload compressed |
| `0x08` | 4 | Payload length, uncompressed (`u32`) |
| `0x0C` | 4 | Payload length, stored (`u32`) |
| `0x10` | 32 | Section directory: 8 entries × `{offset: u16, length: u16}` |

Section offsets are relative to the start of the uncompressed payload, so a loader inflates once and then reads directly. `u16` suffices because the payload never exceeds 64 KiB.

The version is the **disc format's**, in semver, mirroring the binary's scheme, not the console's. It changes only when the layout changes: **major** for a breaking change, **minor** for a backward-compatible addition (a new section id an older loader can skip), **patch** for clarifications that do not affect parsing. A console release that changes no format detail writes the same version it always did.

The version of the console that wrote a disc belongs in `META` as `noka_version=`. Useful for debugging, never a compatibility gate.

### Sections

| Id | Section | Contents |
|----|---------|----------|
| 0 | `META` | `key=value` lines, UTF-8 |
| 1 | `SRC` | NokaScript source, UTF-8, verbatim |
| 2 | `GFX` | Sprite sheet, 1 byte per pixel |
| 3 | `MAP` | Tile indices, 1 byte per tile |
| 4 | `SFX` | Sound bank, as laid out under [Sound](#bank-layout) |
| 5-7 | | Reserved |

A zero length means the section is absent. `GFX`, `MAP`, and `SFX` are copied into their memory regions verbatim on load, no decoding step, no per-pixel transformation.

`META` stays textual because it is small, open-ended, and read by tooling rather than the VM.

### Budget

A disc using every section heavily:

| Section | Bytes |
|---------|-------|
| `SRC` (~8000 tokens) | 16 KiB |
| `GFX` (full 128×128 sheet) | 16 KiB |
| `MAP` (128×64 tiles) | 8 KiB |
| `SFX` (full bank) | 13 KiB |
| `META` + header | < 1 KiB |
| **total** | **~54 KiB** |

Most discs will not use all of these. A game with no music spends that space on sprites instead. Typical discs compress to well under half their content size, but that only affects what is stored, never what fits.

## Token Budget

The editor displays a running token count for the current disc. **8192 tokens** is the target.

This is not enforced. A disc over budget compiles, runs, and distributes exactly like any other. What it does not get is the star.

On save, the count is written to the `META` section as `tokens=N`. Recording it in the file rather than the editor makes it durable and comparable. It travels with the disc and does not require taking anyone's word for it.

A token is anything the scanner emits except end-of-input. Comments and whitespace cost disc bytes but no tokens: **you are never charged for explaining your code.**

## Sound

Eight channels, homogeneous, any instrument plays on any channel. This is the SNES model (its S-DSP had eight identical voices) rather than the Genesis one (fixed-role FM and PSG channels), because uniform channels are simpler to arrange and to store.

| Limit | Value |
|-------|-------|
| Channels | 8 |
| Instruments | 32 |
| Patterns | 64 |
| Rows per pattern | 32 |
| Songs | 8 |
| Order rows per song | 64 |
| Additive partials | 8 |

### Where it runs

The synthesizer runs **host-side on the audio thread**, not in the VM. The VM writes bank data into `SFX` and calls natives (`sfx()`, `music()`); the host reads that region the way the renderer reads `VRAM`.

This is deliberate: a 60 Hz VM and a 44.1 kHz audio thread should never have to agree on timing. The VM posts intent, the host owns the clock.

The engine must be a pure function of its bank, its command sequence, and the number of frames rendered: identical output at any buffer size, with all noise seeded. That property is what lets a second backend exist without sounding different.

### Bank Layout

The bank occupies `SFX` (16 KiB at `0x42000`):

| Offset | Size | Contents |
|--------|------|----------|
| `0x0000` | 256 B | Header: counts, offsets, song table |
| `0x0100` | 1 KiB | 32 instruments × 32 B |
| `0x0500` | 8 KiB | 64 patterns × 32 rows × 4 B |
| `0x2500` | 4 KiB | 8 songs × 64 order rows × 8 channels |
| `0x3500` | ~2.7 KiB | Spare |

### Instruments

32 bytes each. Bytes 0-5 are common; the payload from byte 6 is interpreted according to `kind`.

```
0      kind:2 | wave:3 | echo:1 | spare:2
1      pulse width (pulse) / noise mode
2      AR:4 | DR:4
3      SL:4 | RR:4
4      vol      u8, exponential (dB) curve
5      pan      i8, -128 left .. 127 right
6-13   8 partial amplitudes (additive)
14-31  reserved, see Instrument Roadmap
```

`kind`: 0 basic, 1 additive, 2 noise, 3 FM (reserved).
`wave`: sine, pulse, triangle, saw. Naive and deliberately aliased.

**Pan is signed, and negative volume inverts phase.** The SNES allowed this and composers used it for stereo width. It costs nothing to permit.

Volume maps through an exponential curve, not a linear one. Perceived loudness is logarithmic, and a linear `u8` wastes most of its range in the top octave.

Instrument *names* are editor metadata and do not appear in the packed bank.

### Envelopes

Four fields, four bits each, two bytes total:

```
byte 2: [AR:4][DR:4]      attack rate, decay rate
byte 3: [SL:4][RR:4]      sustain level, release rate
```

The three rates are **indices into a curated exponential table**, not durations. Sixteen attacks exist, spaced so every one is musically useful: the fastest instantaneous, the slowest around four seconds. Sustain level is linear, 0-15 as a fraction of peak.

This is how the S-DSP did it (`AR` 4 bits, `DR` 3, `SL` 3, `SR` 5, whole envelope in two registers) and how the YM2612 did it. The table is a large part of why those machines have a recognizable envelope character: you cannot dial in a bad attack, because the sixteen available ones were chosen.

**Envelope times are absolute, never tempo-relative.** A snare's attack transient is a property of the snare, not the song. Note *durations* are tempo-relative because they are measured in rows; the two axes stay separate.

### Patterns

A pattern is 32 rows of one channel. Patterns double as standalone SFX and as the material songs arrange. One structure, two uses.

Each row is 4 bytes:

```
n:7 | i:5 | v:4 | f:3 | p:8      = 27 bits, 5 spare
```

| Field | Bits | Meaning |
|-------|------|---------|
| `n` | 7 | 0 empty, 1 note-off, 2 continue, 24-108 MIDI note |
| `i` | 5 | Instrument id |
| `v` | 4 | Volume column, 0-15 |
| `f` | 3 | Effect id |
| `p` | 8 | Effect parameter, usually two nibbles |

MIDI notes start at 24, so 0/1/2 are free as sentinels without an offset.

### Effect Columns

| Id | Effect | Parameter |
|----|--------|-----------|
| 0 | none | |
| 1 | slide | ticks to glide from the previous note |
| 2 | vibrato | [speed / depth] |
| 3 | arpeggio | [+hi / +lo] semitones, cycled per tick |
| 4 | volume slide | [up / down] per tick |
| 5 | cut | silence after *n* ticks |
| 6-7 | reserved | |

### Songs

| Field | Encoding |
|-------|----------|
| bpm | `u8`, **+40 offset** → 40-295 BPM |
| ticksPerRow | `u8`, 1-8 |
| loopStart | `u8`, 255 = play once |
| order | 64 rows × 8 channels, `u8` pattern id, 255 = silent |
| echo | delay `u8` (16 ms steps), feedback `u8`, mix `u8` |
| drive | `u8` |

A row is a 16th note, so four rows to the beat. More ticks per row buys finer effect resolution at the same tempo.

BPM as a byte with an offset covers the whole useful range at 1 BPM resolution. Sub-BPM steps would cost top-end range worth more than the precision.

### The Bus Chain

Effects live on the master bus as a **reorderable chain of eight slots**. Order is authored, not fixed.

Order is not a detail. Distortion into a filter sweep is a different instrument than a filter sweep into distortion; delay before overdrive smears its repeats into each other, delay after overdrive keeps them distinct. Any guitarist rearranging a pedalboard is doing exactly this, and the same reasoning holds here.

What makes it affordable is that the bus is **one stereo stream, not eight voices**. A generous roster costs the same as a stingy one.

| Id | Effect |
|----|--------|
| 0 | none: slot inactive |
| 1 | overdrive: tanh soft clip |
| 2 | filter: lowpass / bandpass / highpass, cutoff, resonance |
| 3 | echo return: see below |
| 4 | chorus |
| 5 | phaser |
| 6 | tremolo |
| 7 | compressor |
| 8 | bitcrush |
| 9-15 | reserved |

Routing is 8 slots × `{effect: 4 bits, bypass: 1 bit}`, packed into **8 bytes**. Parameters are 4 bytes per effect. The whole chain, order included, is under 48 bytes per song.

Bypass is distinct from an empty slot so that toggling an effect off preserves both its parameters and its position in the chain.

**Echo is a send, not an insert.** Instruments opt in per-voice with their `echo` flag, as the S-DSP's `EON` register did, which is what lets a dry bass and a wet lead coexist. Slot id 3 places the echo *return* in the chain, exactly like the effects-loop return on a pedalboard, and the reason ordering still works even though the echo itself sits off to the side.

Chain and effect parameters are stored **per song** and applied as **global engine state** when a song loads (the same split the hardware had, where a music driver wrote the DSP's global registers on load).

Per-*instrument* effect racks remain out of scope: those are per-voice, so they cost eight times as much and would not fit a 32-byte instrument. The one exception is the filter, which belongs inside the voice because that is where subtractive synthesis puts it (the same reason a Moog's filter is in the voice and the pedalboard is after the amp).

### Live Modification

`SFX` is writable, and the bank in memory is the bank the synthesizer plays. A running program may rewrite any of it: instrument parameters, modulation amounts, pattern rows, song order, bus chain order. Nothing is frozen at load.

This is not a concession, it is how the hardware worked. A SNES or Genesis music driver was just code writing DSP registers, and dynamic soundtracks of that era were built exactly this way. It makes possible:

- Fully procedural composition: a disc may ship **no pattern data at all** and generate every row from code, reclaiming 8 KiB for other things
- Adaptive music: tempo, instrumentation, or bus order responding to game state
- Sound effects synthesized by code rather than authored
- Register-poking tricks in the demoscene tradition

Writes go to the program's own memory and cost nothing extra. What needs care is *when* they take effect.

#### When writes take effect

Never mid-buffer, and never at a point that would produce a discontinuity. Fields fall into two classes:

**Structural fields take effect at the next note-on** for a voice. A sounding note keeps the instrument it started with, all the way to its release.

```
kind, wave, noise mode, partial count,
envelope rates, FM algorithm
```

**Continuous fields take effect at the next sequencer tick**, smoothed.

```
vol, pan, pulse width, partial amplitudes,
filter cutoff / resonance, mod matrix amounts,
LFO rate and depth, bus effect params, chain order
```

This split is what makes live modulation worth having. Deferring *everything* to the next note would forbid filter sweeps, evolving pads, and any timbral motion during a held note (most of the reason to poke memory in the first place). Deferring nothing would click. Splitting by what physically causes a discontinuity gives both.

The mechanism is a **per-voice snapshot**: at note-on a voice copies the structural fields of its instrument, then reads continuous fields live from the bank. Eight voices × a handful of bytes, and structural immutability during a note falls out for free.

Both boundaries are deterministic functions of sequencer state, so the engine's byte-identical-at-any-buffer-size property survives. Timing depends on the program and the tempo, never on the render chunk size.

Implementations should track dirty 256-byte pages of `SFX` in a single `u64` bitmask and flush changed pages at each tick. At typical tempos that is a few dozen flushes per second, so the audio thread never needs shared access to VM memory, which keeps the design portable across audio backends rather than depending on shared buffers.

#### No clicks

Every known discontinuity has a defined remedy. None of them are left as hardware character.

| Source | Remedy |
|--------|--------|
| Structural change mid-note | Deferred to next note-on via the voice snapshot |
| Parameter jump | One-pole smoothing, so a program writing every frame at 60 Hz glides |
| Voice steal | Short release ramp (~2 ms) before the new note takes the voice |
| Echo delay change | Read pointer glides to the new delay time |

The echo case is worth calling out: gliding the read pointer instead of reallocating produces a **tape-style pitch warble** on the tail as it moves. The S-DSP simply glitched here, and drivers of the era avoided changing delay mid-song. Gliding costs nothing extra, removes the artifact, and turns the remaining behavior into an effect worth reaching for deliberately.

Changing an instrument's `kind` at runtime therefore needs no restriction. The write always succeeds, and it swaps in silently on the next note that uses it.

#### Changes are ephemeral

`DISC` is read-only to the program, so the disc's copy of the bank is the source of truth. Whatever a program scribbles into `SFX` is lost on reload. There is no path by which a running program rewrites its own disc.

### Instrument Roadmap

Bytes 14-31 of an instrument are reserved for deeper sound design, to be added in this order. Each is **fixed-size**: no instrument ever has a variable number of modules, and the signal path is never user-orderable.

**1. Filter** (3 bytes): type (lowpass / bandpass / highpass), cutoff, resonance. Cutoff indexes an exponential table, like the envelope rates. This is the single largest expressive gain per byte: a resonant filter is where subtractive synthesis gets its character, and neither the SNES nor the Genesis had one.

**2. Modulation matrix** (4 slots × 2 bytes): each slot is one byte of `source:4 | dest:4` and one signed byte of amount.

```
sources        LFO1, LFO2, envelope, velocity, note number,
               row position
destinations   pitch, volume, pulse width, filter cutoff,
               filter resonance, partial tilt, pan, echo send
```

Four fixed slots is semi-modular in feel and fixed-size in storage. This is where the expressive depth actually lives, it is what synths like Serum and Massive are really selling, underneath the interface. Free *routing* is a different thing and stays out; it would make instruments variable-length, unbounded in CPU, and impossible to layout in a 24-column editor.

Modulating partial amplitudes deserves special mention: an LFO on partial tilt gives spectral motion, which is the perceptual effect of sweeping a wavetable, for two bytes.

**3. LFOs** (2 × 2 bytes): waveform, rate, retrigger flag.

LFO rate is the one parameter that *should* offer tempo-sync: free-running in Hz from a table, or locked to note divisions (1/1 … 1/32, dotted, triplet). Unlike envelopes, a vibrato or tremolo that drifts against the beat is simply wrong.

**4. FM** (`kind` = 3): four operators with **eight fixed algorithms**, YM2612-style, reinterpreting bytes 6-31 as operator data plus algorithm and feedback.

Fixed algorithms rather than free routing is the historically correct answer and the one that fits: the DX7 was considered capable of nearly any sound with exactly this structure, at roughly thirty bytes a patch.

#### What is deliberately excluded

Per-instrument effect racks, arbitrary module counts, and free modulation routing stay out permanently, not just for now. All three are per-voice or variable-length, and either property breaks the fixed 32-byte instrument and the bounded eight-voice CPU budget.

The master bus is a different matter: it is one stereo stream, so a full reorderable chain there costs almost nothing. See [The Bus Chain](#the-bus-chain).

The expressive range of this machine should come from FM, the voice filter, the modulation matrix, and the order of the bus chain (the same places the hardware it evokes got theirs, plus the one thing a pedalboard taught us the hardware was missing).

## Bytecode Limits

| Limit | Value | Reason |
|-------|-------|--------|
| Code arena | 64 KiB | Exactly u16-addressable |
| Constants | 4096 | Shared program-wide |
| Constant index | u16 | One opcode, no long form |
| Call depth | Bounded by `FRAMES` | |
| Value stack | 256 | |

There is **one code arena for the whole program**, not one per function. A function is an offset and a length into it. This keeps jump operands u16 and arena-absolute, needs no relocation, and makes a function cost about eight bytes instead of a fresh buffer.

The constant pool is likewise single and shared. A u16 index costs one byte more per load than a u8 would, and buys a single `constant` opcode with no long form to special-case in the emitter, the dispatch loop, or the disassembler. A `const_small` immediate covers 0-255 without touching the pool, which is most literals in practice.

The token budget bounds total program bytecode well inside the arena, so overflow is unreachable in practice. The check stays anyway.

## Open Questions

- **Envelope and filter tables.** The sixteen attack/decay/release rates and the filter cutoff curve are specified as "curated exponential tables" but the actual values are not chosen. These determine the console's envelope character and want tuning by ear, not by formula.
- **IO registers.** The layout within `PALETTE` + IO is unassigned beyond the palette itself. Input state, frame counter, and RNG seed want homes here.
- **Audio API surface.** Live modification works through raw writes to `SFX`, which is the fantasy-console idiom and needs no new natives. Whether to also provide structured helpers (`sfx_param`, `pattern_set`) as guardrails over the same bytes is undecided.
- **Palette headroom.** The pixel format is 8bpp, so the palette could widen to 64 or 256 entries without touching the memory map or the cart format. Not planned; noted because the door is already open if it is ever wanted.
- **Disc compression.** The format reserves flags bit 0 for it and the host would do the work, but nothing implements it yet and the VM rejects a disc that still has the bit set. Worth revisiting once real games exist and 65488 bytes starts to bind.
