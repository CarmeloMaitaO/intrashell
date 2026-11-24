# IntraShell Binary Format (ISBF) — Specification

## 0. Conformance

ISBF readers and writers MUST accept all previous major versions of this
specification, and MUST reject any message declaring a future major version.
This policy prevents data corruption caused by reading documents whose wire
format the implementation does not understand.

## 1. Overview

The IntraShell Binary Format (ISBF) is a self-describing, schema-driven,
block-level metaformat optimized for block allocation and concurrent I/O. It
is intended as the paging and framing layer on which developers can build
their own file formats, data stores, filesystems, and communication protocols
from first principles — without reinventing block framing, page recovery, or
endianness handling.

ISBF sits **below** database engines such as SQLite (which provide paging,
B-Trees, transactions, and query layers on top of a block layer) and **above**
encoding rules such as ASN.1 (which describe only field encoding, not block
layout or recovery). In this sense, ISBF is a *metaformat*: dialects define
structure and constraints over built-in data types, and `dialect` objects
(`0x0001`) themselves are ISBF structures.

A central design goal is **zero-copy accessibility**. Fixed slots and
fixed-width elements allow a parser to read any field's value directly from a
memory-mapped file — no deserialization, no intermediate copies, no offset
tables. On a little-endian machine, a `uint32` field at a known offset is
readable in place. This makes ISBF suitable for read-heavy workloads,
embedded systems with tight memory budgets, and any context where per-access
overhead matters.

Bitfields are the one exception: because their subfields share a limb,
extracting a subfield requires a mask-and-shift. Every other built-in data
type is directly readable in place (see Section 10.6 for details).

### 1.1 Document structure

- Sections 2–5 define the wire format, three-tier class model, ID pools, and
  constant IDs common to all ISBF messages.
- Section 6 defines the `Definition` pool (the built-in schema pool used to
  read a `dialect` object and construct a runtime `Dialect` pool).
- Section 7 defines the structure of the `dialect` object (`0x0001`) and
  provides a worked example.
- Sections 8–9 define error handling and security considerations.
- Section 10 records design rationale and scope notes.

## 2. Terminology

- **ISBF dialect**: a binary format defined using a `dialect` object
  (`0x0001`). A dialect specifies the structural types, field ordering, and
  constraints of the messages, objects, and fields that conform to it.
- **Message**: a single ISBF packet or file. It is the root container for the
  header and data sections.
- **Header**: the first section of an ISBF message. It carries the ISBF magic
  bytes, the ISBF version, the dialect magic bytes, and the dialect version.
- **Data**: the second section of an ISBF message. It carries a single main
  object (or a `dialect` object `0x0001` as the main object itself, or a
  `dialect` object `0x0001` as the first field of a main object).
- **Section**: a contiguous group of bytes within a message.
- **Schema**: the shape, field ordering, and constraints of a dialect or
  object.
- **Main object**: a top-level object declared with `is_main = true` in its
  dialect definition, acting as a message-layout rule. A dialect MUST declare
  at least one main object and MAY declare multiple main objects (for
  example, to represent distinct valid message layouts in a protocol). Only
  the last field of a main object may be a flexible-size array.
- **Object**: a heterogeneous, ordered container of fields.
- **Field**: a single data element of a determined type.
- **Limb**: a 16-bit (2-byte) unit. Every field and size measurement is
  expressed in limbs. Limbs are the minimum addressable unit of an ISBF
  message.
- **Slot**: the fixed-size allocation (in limbs) for a field or container,
  declared in the dialect. Every non-flexible-array construct is fixed-size
  and zero-padded when unused.
- **Magic bytes**: four bytes identifying the ISBF format (`['I','S','B','F']`),
  or eight bytes identifying a dialect (derived from the dialect's name via
  truncated SHA-256).
- **ID**: a 16-bit unsigned number that identifies a construct or type within
  an ID pool.
- **Constant IDs**: reserved IDs shared across both the `Definition` and
  `Dialect` pools: `0x0000` (padding/skip), `0x0001` (`dialect` object),
  `0xFFFE` (write in progress), and `0xFFFF` (file termination).
- **`Definition` pool**: the built-in ID pool (`0x0002`–`0xFFFD`, plus
  constant IDs) containing the structural definition objects, comment object,
  and built-in constraint objects used inside a `dialect` object (`0x0001`)
  so the parser can read it and build a runtime `Dialect` pool.
- **`Dialect` pool**: the runtime ID pool (`0x0002`–`0xFFFD`, plus constant
  IDs) constructed from a dialect's definitions, holding the structural types
  and constraint objects defined for that dialect.
- **Metaformat**: a format for defining other formats. ISBF is a metaformat
  because `dialect` objects are themselves ISBF structures.
- **Trace event**: an informational parse event describing what the parser is
  doing. Trace events are not errors; they are emitted only when tracing is
  enabled.
- **Hard error**: a parse failure that prevents further parsing. The parser
  MUST stop immediately.
- **Parseable error**: a parse failure that permits continued parsing. The
  application may inspect the partially-parsed result, or may choose to abort.
- **Zero-copy access**: reading a field's value directly from the underlying
  buffer, without deserialization or copies.

## 3. Endianness

ISBF uses little-endian byte order unconditionally. This applies to:

- Magic bytes (interpreted as a `uint32`)
- IDs (`uint16`)
- Numeric fields of all widths
- Floating-point fields (IEEE 754)
- Bitfield container limbs
- Boolean values

### 3.1 Bit ordering inside bitfields

Subfields within a bitfield are packed starting from the least-significant bit
of the first limb: the first declared subfield occupies bits `[0..N-1]` of
limb 1, the next occupies bits `[N..M-1]`, and so on. A subfield that does
not fit in the remaining bits of a limb continues at bit 0 of the next limb.
Each subfield has a bit-width of `1`–`15` bits, and the bitfield's limb count
is `ceil(sum(subfield widths) / 16)`; trailing bits in the final limb are
implicit zero padding.

### 3.2 Interpreting the magic bytes

The 4-byte magic byte sequence `['I','S','B','F']`, interpreted as a
little-endian `uint32`, has the value `0x46425349`. This value doubles as an
endianness sanity check: a big-endian reader interpreting the same bytes as a
`uint32` would obtain `0x49534246`, which does not match. ISBF mandates that
readers detect this mismatch and reject the message as an endianness
violation.

## 4. Main binary structure

| **Section**       | Header |   Data   |
| ----------------- | ------ | -------- |
| **Size in bytes** |   16   | variable |

An ISBF message is divided into:

1. **Header**: the magic bytes and version for both the ISBF format and the
   dialect.
2. **Data**: the payload.

### 4.1 Header section

| **Field**         | Magic bytes | Version | Dialect's MB | Dialect's version |
| ----------------- | ----------- | ------- | ------------ | ----------------- |
| **Size in bytes** |      4      |    2    |       8      |         2         |

- **Magic bytes**: `['I','S','B','F']`.
- **Version**: a `uint16` carrying the major version of the ISBF
  specification.
- **Dialect's magic bytes**: the eight bytes derived from the dialect's name
  as declared in its `dialect` object. Derivation: encode the name as UTF-8,
  hash with SHA-256, take the first 8 bytes of the digest.
- **Dialect's version**: a `uint16` carrying the major version of the dialect.

The header identifies which dialect is being read. When a message's main
object is a `dialect` object (`0x0001`), that message provides the dialect
definition for the dialect identified by the header.

### 4.2 Data section

The data section begins with a main object (`is_main = true`) or a `dialect`
object (`0x0001`) acting as the main object itself.

A `dialect` object (`0x0001`) may appear in **only two places**:

1. **As the main object itself** at the start of the data section (limb 0 of
   the data section is `0x0001`), defining the dialect.
2. **As the first field of a main object** (and in no other position: never
   nested later in an object, never inside an array, never inside a
   sub-object, and never inside a variant). In this case, the main object's
   own ID limb is at limb 0 of the data section, and the `dialect` object
   (`0x0001`) begins at limb 1 (the second limb of the data section).

Because of this placement rule, if a `dialect` object is present in a
message, its ID (`0x0001`) is guaranteed to appear in either the **first** or
**second** limb of the data section and can be read directly from there.

## 5. Field classes, ID pools, and constants

### 5.1 Three-tier classification of field classes

ISBF classifies field classes into three tiers:

1. **Structural classes** (define layout, ordering, branching, or collections;
   may be declared in a dialect):
   - **Objects**
   - **Bitfields**
   - **Variants**
   - **Arrays**
2. **Data classes** (built into the ISBF parser; carry leaf values and
   length/constraint metadata; cannot be user-defined as new classes in a
   dialect):
   - **Atomic fields**
   - **Container fields**
3. **Marker classes** (built-in constant ID limbs with no payload; each
   marker is simply its ID limb and nothing more):
   - **Padding/skip** (`0x0000`)
   - **Write in Progress (WIP)** (`0xFFFE`)
   - **File termination** (`0xFFFF`)

### 5.2 Constant IDs and the two ID pools

Across the format, **constant IDs** are shared by both ID pools:

- `0x0000`: **Padding/skip** (marker)
- `0x0001`: **`dialect` object** (built-in schema object)
- `0xFFFE`: **Write in Progress (WIP)** (marker)
- `0xFFFF`: **File termination** (marker)

There are **two ID pools**, each using the ID range `0x0002`–`0xFFFD` alongside
the shared constant IDs above:

- **`Definition` pool**: the built-in schema pool for the `dialect` object
  (`0x0001`). It contains the structural definition objects, comment object,
  and built-in constraint objects used inside a `dialect` object so the
  parser can read it and build a runtime `Dialect` pool.
- **`Dialect` pool**: the runtime ID pool for a specific dialect, constructed
  from that dialect's `dialect` object definitions, containing the structural
  types and constraint objects defined for that dialect. Each
  definition/constraint entry carries a `type_id` (`0x0002`–`0xFFFD`)
  assigning its ID in the `Dialect` pool, and member field references resolve
  against the `Dialect` pool rather than the `Definition` pool—so `Dialect`
  pool IDs are independent of `Definition` pool IDs (`0x0002`–`0x0016`) and do
  not collide even if numerically equal.

### 5.3 ID emission rule

**Only Structural and Marker classes carry their ID limb**:

- **Structural classes (Objects, Bitfields, Variants, Arrays)** carry their
  ID limb—including the containing Object's ID, nested Structural fields
  inside an Object, Array element slots, and the active Variant alternative
  ID.
- **Data classes (Atomic and Container)** omit their ID limbs inside Objects;
  their type, ordering, and constraints come from the schema.
- **Marker classes** consist solely of their 1-limb ID (`0x0000`, `0xFFFE`, or
  `0xFFFF`) and nothing more.

Three format rules apply across messages:

> **Fixed-size default.** The ONLY construct in ISBF that is not fixed-size is
> a flexible-size array placed as the **last field of a main object**
> (`is_main = true`). Everything else—including arbitrary-length numbers,
> their constraints, containers, and fixed-size definition arrays—is
> fixed-size and zero-padded.

> **Main object rule.** A dialect MUST declare at least one `is_main = true`
> object and MAY declare multiple `is_main = true` objects. A data section
> carries a main object (or a `dialect` object `0x0001` as the main object
> itself). If a data message's root object is not a main object
> (`is_main = false`), the parser MUST reject it with an error.

> **Structural containment rules.**
> 1. Only **Objects** can contain **Data classes** (Atomic, Container).
>    Objects may also contain nested **Structural classes** (Objects,
>    Bitfields, Variants, Arrays).
> 2. **Variants** can only reference **Objects** or compose other **Variants**
>    (whose leaves are **Objects**). Data classes are never referenced
>    directly by a variant; single-value cases are wrapped in a single-field
>    Object.
> 3. **Arrays** can only contain **Objects** or **Variants**.
> 4. **Bitfields** only define an ordered list of subfield sizes (`1`–`15`
>    bits each).

### 5.4 Marker classes (constant ID limbs only)

- **Padding/skip (`0x0000`)**: a single zeroed limb (`0x0000`) used in empty
  slots or skipped positions. A parser encountering `0x0000` at an ID
  position can skip past the empty slot.
- **Write in Progress / WIP (`0xFFFE`)**: a single `0xFFFE` limb marking a
  slot or element currently undergoing a write/modification.
  - *Creation or append (strictly sequential)*: (1) locate `0xFFFF`, (2)
    allocate space for the new element plus a new `0xFFFF`, (3) write the new
    `0xFFFF` at the new end, (4) change the previous `0xFFFF` to WIP
    (`0xFFFE`), (5) write the element data, (6) replace the WIP ID with the
    element's real ID.
  - *Modification*: (1) set the target ID to WIP (`0xFFFE`), (2) perform the
    modification, (3) restore the real ID.
- **File termination (`0xFFFF`)**: a single `0xFFFF` limb marking the end of
  valid message data so a parser does not read uninitialized trailing space.

### 5.5 Data classes (no ID limb inside objects)

Data classes are built into the ISBF parser and cannot be declared as new
user classes in a dialect. They omit ID limbs inside objects.

- **Atomic fields**: fixed limb count determined by the built-in data type
  and constraint definition (no length prefix). Supports zero-copy access.
- **Container fields**: fixed-slot data (`max_limbs` required in the
  constraint definition) prefixed with a `Size` section measured in **limbs**
  (`int64`, 4 limbs). The magnitude (`abs(size)`) gives the number of used
  value limbs within the fixed `max_limbs` slot; the sign indicates whether
  the last used limb is completely used (`size >= 0`: both bytes used) or
  partially used (`size < 0`: only the first byte of the last limb is used,
  second byte is padding). `size == 0` means empty (`0` limbs). If
  `abs(size) > max_limbs`, emit `0x11`. Supports zero-copy access to the
  active slice.

### 5.6 Structural classes (carry ID limbs)

- **Bitfields**: fixed-size limb container (`ceil(sum(subfield widths) / 16)`
  limbs, trailing bits zero-padded) defined solely as an ordered list of
  subfield bit-widths (`1`–`15` bits each, up to 16 subfields). Each subfield
  is extracted as an unsigned value via mask-and-shift (not zero-copy).
- **Objects**: ordered container of member fields (up to 10 fields; use
  nested objects for composition beyond 10). Carries its own ID limb. Member
  fields of Data classes (Atomic/Container) omit ID limbs; member fields of
  Structural classes (Object/Bitfield/Variant/Array) carry their ID limbs.
  Member fields of Atomic or Container class are zero-copy accessible at
  fixed offsets.
- **Variants**: selects one allowed **Object** type from a list declared in
  the dialect (up to 10 entries; variants may also compose other variants).
  Carries the chosen concrete Object's ID as its ID limb, followed by that
  Object's payload, padded to the largest allowed Object's slot size.
- **Arrays**: holds elements of a single declared **Object** or **Variant**
  type. Carries its own ID limb and a `uint64` (4-limb) element count
  (`Size`), and each element carries its own ID limb (enabling per-element
  WIP tracking).
  - **Flexible-size**: allowed **only** when the array is the **last field**
    of an `is_main = true` Object. Grows/shrinks sequentially at the end of
    the message up to `max_elements`.
  - **Fixed-size**: in **all other positions** (earlier in a `main` object,
    inside an `is_main = false` object, nested in a sub-object, or inside a
    variant). Pre-allocated to `max_elements` slots with unused slots padded
    by `0x0000`.

## 6. The `Definition` pool

ISBF has no separate built-in types section or dialect-sharing dialect.
Instead, the **`Definition` pool** (`0x0002`–`0x0016`, plus shared constant
IDs) defines the comment object, structural definition objects, and built-in
constraint objects used inside a `dialect` object (`0x0001`).

### 6.1 Comment, structural definitions, and constraint objects

- **`0x0002` — Comment object**: built-in object with three fields (IDs
  omitted inside the object):
  1. `target_id` (`uint16`, 1 limb): `0x0000` (unattached/general comment),
     `0x0001` (targets the `dialect` object itself), or `0x0002`–`0xFFFD`
     (targets a definition in the dialect's `Dialect` pool).
  2. `kind` (`uint8`, 1 limb, lower byte): `0x00` (description/documentation),
     `0x01` (name of the target). If `target_id = 0x0001` and `kind = 0x01`,
     the parser MUST reject the message with a hard error (`0x08` if
     embedded, `0x0B` if standalone/pre-shared), because the dialect name is
     declared directly in the `dialect` object (`0x0001`)[span_10](start_span)[span_10](end_span).
  3. Text container (`int64` limb-size + fixed **128-limb** text slot).
- **`0x0003` — Object definition**: declares `type_id` (`0x0002`–`0xFFFD` in
  the `Dialect` pool), `is_main` (`uint16` boolean: `0x0000` = false,
  `0x0001` = true), `field_count` (`uint16`, `1`–`10`), and a fixed-size
  array of **10** member field variant slots (referencing constraint objects
  or structural type IDs in the `Dialect` pool; unused slots zero-padded).
- **`0x0004` — Bitfield definition**: declares `type_id` (`0x0002`–`0xFFFD`
  in the `Dialect` pool), `subfield_count` (`uint16`, `1`–`16`), and a
  fixed-size array of **16** subfield width slots (`1`–`15` bits each; unused
  slots zero-padded). Limb count is `ceil(sum(active widths) / 16)`.
- **`0x0005` — Variant definition**: declares `type_id` (`0x0002`–`0xFFFD`
  in the `Dialect` pool), `option_count` (`uint16`, `1`–`10`), and a
  fixed-size array of **10** allowed **Object** (or composed **Variant**)
  type IDs (`0x0002`–`0xFFFD` in the `Dialect` pool; unused slots
  zero-padded).
- **`0x0006` — Array definition**: declares `type_id` (`0x0002`–`0xFFFD` in
  the `Dialect` pool), `max_elements` (`uint64`), and a single
  `element_type_id` (`0x0002`–`0xFFFD` in the `Dialect` pool) resolving to an
  **Object** or **Variant** definition.

Constraints are treated as built-in objects. Every constraint definition
starts with a `type_id` field (`uint16`, `0x0002`–`0xFFFD` in the `Dialect`
pool) immediately after its definition ID (`0x0007`–`0x0016` in the
`Definition` pool):

- **`0x0007` — `uint8` constraint**: `type_id`, `min` (`uint8`), `max`
  (`uint8`), `parity` (`uint16`: 0=any, 1=even, 2=odd), `multiple_of`
  (`uint8`; 0=none).
- **`0x0008` — `uint16` constraint**: `type_id`, `min` (`uint16`), `max`
  (`uint16`), `parity` (`uint16`), `multiple_of` (`uint16`; 0=none).
- **`0x0009` — `uint32` constraint**: `type_id`, `min` (`uint32`), `max`
  (`uint32`), `parity` (`uint16`), `multiple_of` (`uint32`; 0=none).
- **`0x000A` — `uint64` constraint**: `type_id`, `min` (`uint64`), `max`
  (`uint64`), `parity` (`uint16`), `multiple_of` (`uint64`; 0=none).
- **`0x000B` — `int8` constraint**: `type_id`, `min` (`int8`), `max`
  (`int8`), `parity` (`uint16`), `multiple_of` (`int8`; 0=none).
- **`0x000C` — `int16` constraint**: `type_id`, `min` (`int16`), `max`
  (`int16`), `parity` (`uint16`), `multiple_of` (`int16`; 0=none).
- **`0x000D` — `int32` constraint**: `type_id`, `min` (`int32`), `max`
  (`int32`), `parity` (`uint16`), `multiple_of` (`int32`; 0=none).
- **`0x000E` — `int64` constraint**: `type_id`, `min` (`int64`), `max`
  (`int64`), `parity` (`uint16`), `multiple_of` (`int64`; 0=none).
- **`0x000F` — `float32` constraint**: `type_id`, `min` (`float32`), `max`
  (`float32`).
- **`0x0010` — `float64` constraint**: `type_id`, `min` (`float64`), `max`
  (`float64`).
- **`0x0011` — Natural constraint (fixed limb count)**: `type_id`,
  `limb_count` (`uint16`), `min_pow10` (`uint16`), `parity` (`uint16`).
- **`0x0012` — Integer constraint (fixed limb count)**: `type_id`,
  `limb_count` (`uint16`), `min_pow10` (`uint16`), `parity` (`uint16`).
- **`0x0013` — Rational constraint (fixed limb counts)**: `type_id`,
  `num_limbs` (`uint16`), `den_limbs` (`uint16`), `min_pow10` (`uint16`),
  `parity` (`uint16`), `must_be_reduced` (`uint16`: 0 or 1).
- **`0x0014` — BLOB constraint**: `type_id`, `min_limbs` (`uint64`),
  `max_limbs` (`uint64`, **required**; sets the fixed limb count of the
  container's value slot alongside its 4-limb `int64` `Size` prefix).
- **`0x0015` — UTF-8 string constraint**: `type_id`, `min_limbs` (`uint64`),
  `max_limbs` (`uint64`, **required**; sets the fixed limb count of the
  container's value slot alongside its 4-limb `int64` `Size` prefix),
  `range_count` (`uint16`, `0`–`10`; `0` means all valid Unicode scalar
  values are allowed), and up to **10** `{start: uint32, end: uint32}`
  ranges.
- **`0x0016` — Boolean constraint**: `type_id` only. No further constraint
  fields exist; a boolean is strictly a `0x0000` or `0x0001` limb.

## 7. The `dialect` object (`0x0001`)

There is no separate built-in dialect just for sharing dialects. Instead, the
header identifies which dialect is being read, and finding a `dialect` object
(`0x0001`) as the main object (or as the first field of a main object)
indicates the dialect definition for that dialect.

### 7.1 Structure and placement of the `dialect` object (`0x0001`)

A `dialect` object (`0x0001`, `is_main = true`) contains:
1. Object ID limb `0x0001`.
2. Dialect name container (Data class; ID omitted inside the object): 4-limb
   `int64` `Size` + fixed **128-limb** text slot (`132` limbs total), whose
   SHA-256 first 8 bytes MUST match the header's Dialect MB.
3. Dialect version (`uint16`, Data class; ID omitted inside the object), which
   MUST match the header's Dialect version.
4. Definitions array (Structural class; ID carried), containing structural
   definitions (`0x0003`–`0x0006`), comment objects (`0x0002`, with
   `target_id != 0x0001` or `kind != 0x01`), and constraint objects
   (`0x0007`–`0x0016`), each starting with its `type_id` (`0x0002`–`0xFFFD`)
   immediately after its definition ID to assign its ID in the dialect's
   `Dialect` pool.

A `dialect` object (`0x0001`) may appear **only** as the main object itself
(limb 0 of the data section) or as the **first field** of a main object (limb
1 of the data section), guaranteeing it is in the first or second limb of the
data section.

### 7.2 Worked example (`io.intrashell.example.person`)

Consider a dialect named `io.intrashell.example.person` (version `1`)
defining a main `Person` object (`type_id = 0x0100`, `is_main = true`) with
two fields:
- `name`: UTF-8 string constraint (`0x0015`, `type_id = 0x0101`),
  `min_limbs = 0`, `max_limbs = 32` (fixed 32-limb value slot + 4-limb
  `int64` `Size`), `range_count = 0`.
- `age`: `uint8` constraint (`0x0007`, `type_id = 0x0102`), `min = 0`
  (`uint8`), `max = 255` (`uint8`), `parity = 0`, `multiple_of = 0`
  (`uint8`).

Element limb sizes in the definitions array:
- `0x0015` UTF-8 string constraint (`0x0101`): `1 + 1 + 4 + 4 + 1 + 40 = 51` limbs.
- `0x0007` `uint8` constraint (`0x0102`): `1 + 1 + 1 + 1 + 1 + 1 = 6` limbs.
- `0x0003` Object definition (`0x0100`): `1 + 1 + 1 + 1 + 10 = 14` limbs.
- `0x0002` Comment object (`target_id = 0x0100`, `kind = 0x00`): `1 + 1 + 1 + 4 + 128 = 135` limbs.

The largest element is **135 limbs**, so each slot in this definitions array
is sized to **135 limbs** (zero-padded).

Inside the `dialect` object (`0x0001`):
1. The **Header** (16 bytes) has magic `['I','S','B','F']`, ISBF version `1`,
   Dialect MB `SHA-256("io.intrashell.example.person")[0..8]`, and Dialect
   version `1`.
2. The **Data section** begins with `0x0001` (`dialect` object ID), followed
   by the dialect name container (`Size = +14`, 128-limb slot containing
   `io.intrashell.example.person`, no ID limb), version `1` (`uint16`, no ID
   limb), and the definitions array (with its ID limb; 135-limb slots)
   containing:
   - Constraint definition `0x0015` followed immediately by
     `type_id = 0x0101` (`51` limbs, padded to `135` limbs).
   - Constraint definition `0x0007` followed immediately by
     `type_id = 0x0102` (`6` limbs, padded to `135` limbs).
   - Object definition `0x0003` followed immediately by `type_id = 0x0100`
     (`is_main = true`, `field_count = 2`, 10-slot member array referencing
     `0x0101` and `0x0102`; `14` limbs, padded to `135` limbs).
   - Optional Comment object `0x0002` with `target_id = 0x0100` and
     `kind = 0x00` (description), `Size`, and 128-limb text slot (`135`
     limbs).
3. The message ends with `0xFFFF`.

A `Person` message under this dialect begins with its 16-byte header,
followed in the data section by `0x0100` (`Person` object ID), `name`
(`int64` limb-size + fixed `32`-limb slot, no ID limb), `age` (`uint8` value
in 1 limb, no ID limb), and `0xFFFF`.

## 8. Error handling and trace events

The parser reports its state through 8-bit codes across four categories:

- **Success (`0x01`)**: clean parse completion.
- **Trace events (`0x02`–`0x24` subset)**: informational events emitted only
  when tracing is enabled; never returned as errors.
- **Hard errors**: parse failures that prevent further parsing; parser MUST
  stop immediately and return the code.
- **Parseable errors**: parse failures that permit continued parsing; caller
  may inspect partial results and decide whether to abort, log, or recover.

### 8.1 Success

| Code   | Name | Category |
| ------ | ---- | -------- |
| `0x01` | Ok   | Success  |

### 8.2 Trace events

| Code   | Name                                | Category |
| ------ | ----------------------------------- | -------- |
| `0x02` | Found header                        | Trace    |
| `0x04` | Supported ISBF version found        | Trace    |
| `0x07` | Found embedded dialect              | Trace    |
| `0x0A` | Dialect valid                       | Trace    |
| `0x0C` | Found atomic field                  | Trace    |
| `0x0D` | Atomic field's value is valid       | Trace    |
| `0x0F` | Found container field               | Trace    |
| `0x10` | Container field's size is valid     | Trace    |
| `0x12` | Found bitfield field                | Trace    |
| `0x13` | Found bitfield's subfield           | Trace    |
| `0x14` | Bitfield's subfield value is valid  | Trace    |
| `0x16` | Found object field                  | Trace    |
| `0x17` | Found variant field                 | Trace    |
| `0x18` | Variant field's value/ID is valid   | Trace    |
| `0x1A` | Found array field                   | Trace    |
| `0x1B` | Array field's size is valid         | Trace    |
| `0x1D` | Found padding/skip field            | Trace    |
| `0x1F` | Found file termination field        | Trace    |

### 8.3 Hard errors

| Code   | Name                                | Category |
| ------ | ----------------------------------- | -------- |
| `0x03` | Header not found                    | Hard     |
| `0x05` | Unsupported ISBF version found      | Hard     |
| `0x08` | Invalid embedded dialect            | Hard     |
| `0x09` | Dialect beyond size constraint      | Hard     |
| `0x0B` | Dialect invalid                     | Hard     |
| `0x24` | File is beyond the size constraint  | Hard     |
| `0x25` | Allocation budget exceeded          | Hard     |
| `0x26` | Header and dialect don't match      | Hard     |

### 8.4 Parseable errors

| Code   | Name                                 | Category  |
| ------ | ------------------------------------ | --------- |
| `0x06` | Unrecognized dialect's MB            | Parseable |
| `0x0E` | Atomic field's value is invalid      | Parseable |
| `0x11` | Container field's size is invalid    | Parseable |
| `0x15` | Bitfield's subfield value is invalid | Parseable |
| `0x19` | Variant field's value/ID is invalid  | Parseable |
| `0x1C` | Array field's size is invalid        | Parseable |
| `0x1E` | Found padding/skip at an ID limb     | Parseable |
| `0x20` | Found file termination prematurely   | Parseable |
| `0x21` | Found WIP field                      | Parseable |
| `0x22` | Unrecognized ID                      | Parseable |
| `0x23` | Couldn't allocate more space         | Parseable |

### 8.5 Numbering stability

Error code assignments are stable across revisions. New codes may be added at
`0x27` and above; existing codes will not be reassigned. Implementations may
add implementation-specific diagnostic codes at `0x80` and above if clearly
documented.

## 9. Security

### 9.1 Integer overflow in field size

A parser MUST reject messages in which any field's `Size` section exceeds the
bounds of the field, emitting `0x11` for containers and `0x1C` for arrays.

### 9.2 Recursive object definitions

A parser MUST reject dialect definitions with cyclic/self-referential nesting
at the same taxonomical level, emitting `0x08` for embedded `dialect` objects
(`0x0001`) and `0x0B` for standalone/pre-shared dialect definitions.

### 9.3 Header and dialect mismatch

When reading a `dialect` object (`0x0001`), a parser MUST derive the magic
bytes from the dialect's 128-limb name field (first 8 bytes of SHA-256) and
compare both the derived magic bytes and the dialect version against the
header's Dialect MB and Dialect version. If either does not match, the parser
MUST stop immediately and emit hard error `0x26` (*Header and dialect don't
match*).

### 9.4 Dialect magic byte collision

Because dialect magic bytes are derived by truncating SHA-256 to 8 bytes,
parsers MUST support:
- Opening with a pre-shared dialect and ignoring embedded `dialect` objects
  (default).
- Opening and parsing with an embedded `dialect` object (when present in
  limb 0 or limb 1 of the data section).
- Opening and ignoring dialect definitions (inspection mode).

### 9.5 Embedded dialect size limit

Parsers MUST accept a per-call size limit (default **1 MB**) for reading a
`dialect` object (`0x0001`) before parsing it, rejecting oversized
definitions with hard error `0x09`.

### 9.6 Fixed-size array allocation bounds

Parsers MUST accept a per-call **allocation budget** (defaulting to the
embedded-dialect limit, 1 MB) and perform a pre-flight size check across
object slots, fixed-size arrays, and variants before allocating or traversing
memory, returning `0x25` if exceeded.

### 9.7 File termination inside variants

`0xFFFF` MUST NOT appear as an allowed variant alternative or active variant
ID limb; if encountered within a variant field, the parser MUST emit `0x20`.

## 10. Notes

### 10.1 Versioning of ISBF and its dialects

Versions use `Major.Revision`, where `Major` identifies the format/dialect
revision enforced by parsers and `Revision` tracks specification document
revisions.

### 10.2 Design rationale

ISBF acts as a block-level metaformat substrate—below databases like SQLite
(no B-trees, query planner, or built-in WAL) and above pure field encoders
like ASN.1—so developers can build data stores, filesystems, and protocols on
a shared limb-aligned foundation.

### 10.3 Bootstrapping the `Definition` pool

The parser hard-codes the `Definition` pool rules (`0x0002`–`0x0016`),
constant IDs (`0x0000`, `0x0001`, `0xFFFE`, `0xFFFF`), and `0x0001` `dialect`
object layout so it can read any `dialect` object, construct the runtime
`Dialect` pool, and parse messages for that dialect.

### 10.4 Concurrency

Because `0xFFFE` (WIP) in memory/storage is not nanosecond-atomic across
threads/processes, parsers/writers should pair WIP markers with a lock-free
tracking structure (such as a lock-free circular list of in-flight slots) and
enforce sequential appends with a lock.

### 10.5 ACID and Storage Engine Primitives

ISBF provides the foundational primitives for storage engines, but
deliberately delegates higher-level algorithms to the developer building the
dialect and system on top of it. Specifically:

- **Write-Ahead Logging (WAL) & Transactions:** ISBF provides the WIP
  slot-level atomic primitive. Multi-slot transactions and WAL staging
  buffers must be implemented by the developer. The ISBF layout enables this
  by allowing developers to store a WAL in a flexible array or an isolated
  file block.
- **Paging:** Paging is natively supported via flexible arrays. A dialect can
  declare a flexible array of 4KB (or 8KB/16KB) container elements. The
  developer manages the mapping of logical pages to these array indices.
- **MVCC (Multi-Version Concurrency Control):** Arrays carry ID limbs for
  every element. Combined with WIP markers, this enables developers to
  implement MVCC by tracking element versions and locking specific array
  slots without affecting other elements.
- **Free Space Management & Allocators:** The `0x0000` (Padding/Skip) marker
  acts as the primitive for unallocated or free space. The developer is
  responsible for implementing the actual allocator (e.g., a free-list, a
  bitmap, or an extent tree) that tracks these padding slots.
- **Extent Coalescence:** When freeing adjacent blocks, the developer's
  allocator should coalesce adjacent `0x0000` padding slots into larger
  extents to prevent fragmentation.
- **Sparse Files & Hole Punching:** Because the parser relies on
  dialect-inferred offsets and the `0xFFFF` terminator rather than the
  OS-reported file size, developers can natively use OS-level sparse file
  allocation. Empty spaces containing `0x0000` do not need to be physically
  written to the disk.

### 10.6 Zero-copy design

Fixed slots, 16-bit limb alignment, little-endian layout, and `int64`
limb-size prefixes on containers enable direct pointer/slice reads without
deserialization. Bitfields require bit-masking and shifting to extract
subfields as naturals, and flexible trailing arrays on `is_main = true`
objects can shift offsets on append/shrink, so callers holding references
across mutations should re-resolve after writes.
