# IntraShell Binary Format (ISBF) — Specification V1.0

## 0. Conformance

ISBF readers and writers MUST accept all previous major versions of this specification, and MUST reject any message declaring a future major version. This policy prevents data corruption caused by reading documents whose wire format the implementation does not understand.

## 1. Overview

The IntraShell Binary Format (ISBF) is a self-describing, schema-driven, block-level metaformat optimized for block allocation and concurrent I/O. It is intended as the paging and framing layer on which developers can build their own file formats, data stores, filesystems, and communication protocols from first principles — without reinventing block framing, page recovery, or endianness handling.

ISBF sits **below** database engines such as SQLite (which provide paging, B-Trees, transactions, and query layers on top of a block layer) and **above** encoding rules such as ASN.1 (which describe only field encoding, not block layout or recovery). In this sense, ISBF is a *metaformat*: it is used to define dialects, and those dialects are themselves ISBF documents.

A central design goal is **zero-copy accessibility**. Fixed slots and fixed-width elements allow a parser to read any field's value directly from a memory-mapped file — no deserialization, no intermediate copies, no offset tables. On a little-endian machine, a `uint32` field at a known offset is readable in place. This makes ISBF suitable for read-heavy workloads, embedded systems with tight memory budgets, and any context where per-access overhead matters.

Bitfields are the one exception: because their subfields share a limb, extracting a subfield requires a mask-and-shift. Every other built-in type is directly readable in place (see Section 10.5 for details).

### 1.1 Document structure

- Sections 2–5 define the wire format common to all ISBF messages.
- Section 6 defines the built-in types and the reserved ID space.
- Section 7 defines the interface definition dialect: the built-in ISBF dialect used to declare new dialects.
- Sections 8–9 define error handling and security considerations.
- Section 10 records design rationale and scope notes.

## 2. Terminology

- **ISBF dialect**: a binary format defined using an ISBF interface description file. A dialect specifies the shape and constraints of the messages, sections, objects, and fields that conform to it.
- **Interface description file**: an ISBF message whose dialect magic bytes are all-zeros (`[0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00]`). It contains the declaration of a dialect and is itself a valid ISBF message.
- **Message**: a single ISBF packet or file. It is the root container for the header and data sections.
- **Header**: the first section of an ISBF message. It carries the ISBF magic bytes, the ISBF version, the dialect magic bytes, and the dialect version.
- **Data**: the second section of an ISBF message. It carries a single main field or object from the dialect, optionally preceded by an embedded dialect preamble (see Section 4.2).
- **Section**: a contiguous group of bytes within a message.
- **Schema**: the shape and constraints of a message, section, or object.
- **Object**: a heterogeneous, ordered container of fields.
- **Field**: a single data element of a determined type.
- **Limb**: a 16-bit (2-byte) unit. Every field is composed of one or more limbs. Limbs are the minimum addressable unit of an ISBF message.
- **Slot**: the fixed-size allocation for a field, declared in the dialect. A field occupies its full slot regardless of the amount of data it actually uses. Padding within a slot is implicit.
- **Magic bytes**: four bytes identifying the ISBF format (`['I','S','B','F']`), or eight bytes identifying a dialect (derived from the dialect's name via truncated SHA-256).
- **ID**: a 16-bit unsigned number that identifies a section, object, or field.
- **Metaformat**: a format for defining other formats. ISBF is a metaformat because dialects are themselves ISBF documents.
- **Field mechanism**: a reserved built-in ID whose value is not instantiable by user dialects, and which exists to support a structural role. `0x0001` (dialect preamble) and `0x0012` (dialect reference) are field mechanisms.
- **Trace event**: an informational parse event describing what the parser is doing. Trace events are not errors; they are emitted only when tracing is enabled.
- **Hard error**: a parse failure that prevents further parsing. The parser MUST stop immediately.
- **Parseable error**: a parse failure that permits continued parsing. The application may inspect the partially-parsed result, or may choose to abort.
- **Zero-copy access**: reading a field's value directly from the underlying buffer, without deserialization or copies.

## 3. Endianness

ISBF uses little-endian byte order unconditionally. This applies to:

- Magic bytes (interpreted as a `uint32`)
- IDs (`uint16`)
- Numeric fields of all widths
- Floating-point fields (IEEE 754)
- Bitfield container limbs
- Boolean values

### 3.1 Bit ordering inside bitfields

Subfields within a bitfield are packed starting from the least-significant bit of the first limb: the first declared subfield occupies bits `[0..N-1]` of limb 1, the next occupies bits `[N..M-1]`, and so on. A subfield that does not fit in the remaining bits of a limb continues at bit 0 of the next limb. The total declared width of all subfields MUST equal the declared limb count of the bitfield times 16.

### 3.2 Interpreting the magic bytes

The 4-byte magic byte sequence `['I','S','B','F']`, interpreted as a little-endian `uint32`, has the value `0x46425349`. This value doubles as an endianness sanity check: a big-endian reader interpreting the same bytes as a `uint32` would obtain `0x49534246`, which does not match. ISBF mandates that readers detect this mismatch and reject the message as an endianness violation.

## 4. Main binary structure

| **Section**       | Header |   Data   |
| ----------------- | ------ | -------- |
| **Size in bytes** |   16   | variable |

An ISBF message is divided into:

1. **Header**: the magic bytes and version for both the ISBF format and the dialect.
2. **Data**: the actual data.

### 4.1 Header section

| **Field**         | Magic bytes | Version | Dialect's MB | Dialect's version |
| ----------------- | ----------- | ------- | ------------ | ----------------- |
| **Size in bytes** |      4      |    2    |       8      |         2         |

- **Magic bytes**: `['I','S','B','F']`.
- **Version**: a `uint16` carrying the major version of the ISBF specification. This document defines version `1`.
- **Dialect's magic bytes**: the eight bytes derived from the dialect's name as declared in the interface description file. Derivation: encode the name as UTF-8, hash with SHA-256, take the first 8 bytes of the digest.
- **Dialect's version**: a `uint16` carrying the major version of the dialect.

### 4.2 Data section

The data section carries the payload. Its structure depends on whether the file is self-describing or plain:

- **Self-describing file**: the data section begins with an embedded dialect preamble (a single `0x0001` field carrying a `dialect` object, see Section 6.3), immediately followed by the single main field or object that the dialect declares.
- **Plain file**: the data section contains only the single main field or object that the dialect declares; the schema is external.

In both cases, the main field is exactly one field or object. The embedded preamble, when present, is a mechanism — it carries the dialect's declaration so the file remains readable even if the original dialect definition is lost. It is *not* part of the dialect's declared data, and it does not count as a "main field." Whether to embed it is the writer's decision, typically driven by the developer's intent (for example, when the developer asks the writer to produce a self-describing save file or export).

## 5. Field classes

Every field is wrapped in a container composed of an array of 16-bit limbs. The number of limbs is `ceil(fieldSize / 2)`, so every field is 16-bit aligned and padding is implicit. Each field is preceded by a single-limb ID. The basic form of any field is:

| **Semantic value** | ID |  Value   |
| ------------------ | -- | -------- |
| **Size in limbs**  | 1  | variable |

A field's class determines how its `Value` section is structured. The classes are:

- Padding/skip
- File termination
- Write in Progress (WIP)
- Atomic fields
- Container fields
- Bitfields
- Objects
- Variants
- Arrays

Two rules apply across all classes:

> **Fixed slots.** Every field, object, and type MUST declare a fixed size in its dialect. This enables concurrent writes to specific slots and is a prerequisite for zero-copy access. The only exception is appending at end-of-file, which is strictly sequential.

> **Single main field.** An ISBF message's data section carries exactly one main field or object (plus an optional preceding dialect preamble; see Section 4.2). Multiple records are expressed by wrapping them in a Variant or an Array.

### 5.1 Padding/skip

An empty slot in any of the other classes is filled with padding limbs. Each padding limb is fully zeroed (`0`), so its ID is `0x0000`. A parser that encounters a padding ID at the position where a field ID would be can skip past the corresponding slot without reading its contents, regardless of whether the field is fixed- or flexible-sized.

> The padding/skip class is a reserved type. It cannot be declared as the base class of any user field.

### 5.2 File termination

The ID `0xFFFF` marks the actual end of the file. Although the filesystem reports the file size, the termination limb exists so a parser does not read random data from a memory allocation that has not yet been overwritten.

> The file termination class is a reserved type. It cannot be declared as the base class of any user field.

### 5.3 Write in Progress (WIP)

Every create, append, or modify operation that touches the file is wrapped in a recovery protocol designed to survive a crash, power outage, or forced shutdown. The protocol uses the WIP ID `0xFFFE` to signal which element is mid-write. In a crash, the specific corrupted object or field is singled out, and the system may decide how to recover.

**Creation or append (strictly sequential):**

1. Locate the file termination limb.
2. Allocate space for the new object/field plus a new termination limb.
3. Write the new termination limb at the new last position.
4. Rewrite the previous termination limb as a WIP ID.
5. Write the data to the object/field.
6. Change the WIP ID to the field's real ID.

**Modification (concurrency enabled):**

1. Change the field's ID to WIP (`0xFFFE`).
2. Perform the modification.
3. Change the ID back to its original value.

The WIP ID thus acts as a per-slot mutex. Its absence means the slot is free.

> The WIP class is a reserved type. It cannot be declared as the base class of any user field.

### 5.4 Atomic fields

Atomic fields are the simplest non-reserved class. Their `Value` section is fixed-size and carries the field's data directly, with no size subfield.

| **Semantic value** | ID |  Value   |
| ------------------ | -- | -------- |
| **Size in limbs**  | 1  |  Fixed   |

Atomic fields are the only class that does not declare whether the last limb is partially used: the field's slot size is fully determined by its type, and any unused bits at the end are implicit padding. Atomic fields are the primary vehicle for zero-copy access.

### 5.5 Container fields

A container field is like an atomic field but with an explicit `Size` section. It is used for fixed-slot fields whose actual data may occupy fewer bytes than the slot.

The `Size` section is an `int64` whose sign and magnitude carry two pieces of information:

- **Magnitude** (`abs(size)`): the number of value limbs in use.
- **Sign**: whether the last value limb is fully or partially used. A non-negative value means the last value limb is fully used (both bytes carry data). A negative value means only the first byte of the last limb is used (the second byte is padding).

A size of `0` (magnitude 0, non-negative) means the container holds no data. A size of `0` with a negative sign is contradictory — there is no last limb to be partially used — and MUST be rejected as a parseable error (`0x11`).

| **Semantic value** | ID | Size (`int64`) | Value limbs |
| ------------------ | -- | -------------- | ----------- |
| **Size in limbs**  | 1  |        4       |   Fixed     |

The container has a fixed slot size; the data *within* it may vary. The `Size` section tells the parser how much of the container's slot is actually used, and whether the final used limb is fully or partially filled.

Containers are zero-copy accessible. Because the `Size` field is a single `int64`, the parser reads it as one 8-byte value, extracts the magnitude and the flag with one sign test, and — for fully-used containers — reads the value bytes directly from their fixed offset. Partially-used containers expose a length (`abs(size) × 2 − 1` bytes) plus a pointer; the bytes themselves remain in place.

### 5.6 Bitfields

A bitfield is a fixed-size bit pattern partitioned into named, non-overlapping subfields, each of which is an unsigned integer no larger than 15 bits. This mirrors the object/tuple model at bit granularity, with each subfield representing an integer.

| **Semantic value** | ID |   Limbs  |
| ------------------ | -- | -------- |
| **Size in limbs**  | 1  |   Fixed  |

The bitfield's limb count is determined by the sum of the subfields' declared widths (see Section 3.1 for packing order). Subfields carry no ID, only a value; the per-subfield structure is declared in the dialect's interface description file.

Bitfields are **not** zero-copy accessible: extracting a subfield requires a mask-and-shift because the subfield shares a limb with its neighbours. Bitfields are provided for compactness. Callers that need in-place access should use atomic fields and accept the space cost.

### 5.7 Objects

An object is a fixed-size container of fields, each of which may be of any class (including other objects). Fields inside an object omit their ID limbs: the field's position in the object is its identity.

| **Semantic value** | ID | Fields (without their IDs) |
| ------------------ | -- | -------------------------- |
| **Size in limbs**  | 1  |           Fixed            |

Because object fields have no ID limb, they require fewer limbs than the same fields at the top level, where an ID is mandatory. The field order is declared in the dialect, and that order is what determines each field's position and type during parsing.

Object fields whose types are atomic or container are zero-copy accessible (each field's slot has a fixed offset within the object).

### 5.8 Variants

A variant is a field whose concrete type is one of a list of allowed types declared in the dialect. It is the ISBF equivalent of Nim's object variants. The variant's ID limb carries the ID of the concrete type that was chosen for this instance; the field's payload is the concrete type's payload.

| **Semantic value** | ID of the field type |       Field       |
| ------------------ | -------------------- | ----------------- |
| **Size in limbs**  |           1          |       Fixed       |

Variants are **always fixed-size**, regardless of where they are placed (nested in an object, inside an array, or at the top level). The variant's slot is always the size of its largest allowed alternative. Smaller alternatives are padded within the slot.

When the chosen alternative is atomic or container, the payload is zero-copy accessible at a fixed offset.

### 5.9 Arrays

An array is a container of elements of a single declared type. Its `Size` section is a `uint64` representing the number of elements stored from the start of the container.

Two forms exist:

- **Fixed-size array**: the array's physical slot is pre-allocated to `max_elements × element_slot_size` and never changes. The `Size` section reports how many elements are actually used, from the start of the array. Unused slots are padding. The file's byte size is stable regardless of the number of used elements.
- **Flexible-size array**: the array's physical slot grows and shrinks with the number of used elements. The `Size` section reports the number of used elements. The file's byte size changes as elements are added or removed. The declared `max_elements` is a **validation upper bound**, not a pre-allocation: it constrains how many elements the array can hold, but does not reserve space for them.

Which form an array takes is determined by its position in the dialect:

- **Flexible-size**: only when the array is the **last field of the top-level object** (the sole main field of the data section). This is the only position where the containing structure's size can change without invalidating already-parsed offsets or zero-copy references — because the array grows by appending to the end of the file, and no subsequent fields exist to be shifted.
- **Fixed-size**: in every other position — including arrays in the middle of the top-level object, arrays nested inside other objects, and arrays selected by a variant.

Array elements keep their ID limbs, so they can individually be changed to WIP during concurrent writes. In a fixed-size array, unused slots are padding; in a flexible-size array, the physical slot ends at the last used element's last limb.

**Fixed-size array structure:**

| **Semantic value** | ID | Size (`uint64`) |  Elements (with their IDs)  |
| ------------------ | -- | --------------- | --------------------------- |
| **Size in limbs**  | 1  |        4        |            Fixed            |

**Flexible-size array structure:**

| **Semantic value** | ID | Size (`uint64`) |  Elements (with their IDs)  |
| ------------------ | -- | --------------- | --------------------------- |
| **Size in limbs**  | 1  |        4        |          Variable           |

## 6. Built-in types and reserved IDs

### 6.1 Reserved IDs

The ISBF reserves the following IDs across all dialects:

- `0x0000`: padding/skip
- `0xFFFE`: write in progress (WIP)
- `0xFFFF`: file termination
- `0x0001` to `0x00FF`: reserved for built-in types

Dialect-declared types MUST use IDs in the range `0x0100` to `0xFFFD`.

### 6.2 Built-in types

- `0x0001` (container, **field mechanism**): ISBF dialect preamble. Used only as the first field of a message's data section, to carry the dialect's `dialect` object. Not instantiable by user dialects; see 6.3.
- `0x0002` (container): BLOB
- `0x0003` (container): UTF-8 string
- `0x0004` (atomic): 16-bit boolean (`0x0000` = false, `0x0001` = true; any other value is a parseable error `0x0E`)
- `0x0005` (atomic): arbitrary-length natural
- `0x0006` (atomic): arbitrary-length integer
- `0x0007` (atomic): arbitrary-length rational
- `0x0008` (atomic): unsigned 8-bit integer
- `0x0009` (atomic): unsigned 16-bit integer
- `0x000A` (atomic): unsigned 32-bit integer
- `0x000B` (atomic): unsigned 64-bit integer
- `0x000C` (atomic): signed 8-bit integer
- `0x000D` (atomic): signed 16-bit integer
- `0x000E` (atomic): signed 32-bit integer
- `0x000F` (atomic): signed 64-bit integer
- `0x0010` (atomic): 32-bit float
- `0x0011` (atomic): 64-bit float
- `0x0012` (atomic, **field mechanism**): dialect reference. Used only within interface definition files as a field alternative (see 7.6.4). Not instantiable by user dialects; it exists solely to express references inside interface definitions.

### 6.3 The `0x0001` interface definition preamble

The `0x0001` type is a **field mechanism**, like `0x0012` (dialect reference). It is not instantiable by user dialects; it exists solely to carry a `dialect` object as an embedded preamble at the start of a message's data section.

When present, it MUST be the first field of the data section. Its payload is a single `dialect` object (ID `0x0100`, see Section 7.2) — the same object type used to declare dialects standalone. No ISBF header accompanies the embedded dialect: the outer message's header carries the dialect MB and version, which are derived from the embedded dialect's name and version, respectively.

A file that wants to be self-describing places a `0x0001` preamble as the first field of its data section, followed by the actual data field (see Section 4.2). A file that does not embed its schema puts only the data field; the schema must be available externally. Whether to embed the preamble is the writer's decision, typically driven by the developer's intent.

The presence of the preamble is detected by checking whether the first field of the data section has ID `0x0001`. If it does, the parser reads the `dialect` object first and then parses the following field as the main data. If it does not, the first field is the main data.

### 6.4 Arbitrary-length numbers

The Natural (`0x0005`), Integer (`0x0006`), and Rational (`0x0007`) types share a single wire structure:

| **Section**       | Sign and limbs |       Number       |
| ----------------- | -------------- | ------------------ |
| **Size in limbs** |       1        | As declared by the dialect's `Limb count` constraint |

The first limb ("sign and limbs") is an `int16`:

- Its absolute value is the total number of value limbs that follow.
- Its sign is the number's sign.

**Canonical form** (mandatory):

- The absolute value of the sign-and-limbs limb MUST equal the `Limb count` constraint declared in the dialect for this type. A parser MUST reject any number whose declared limb count does not match (error `0x0E`).
- Value limbs are LSB-first: limb 0 is least-significant; the last limb is most-significant.
- Leading zero limbs are **permitted** and **required** when the value needs fewer limbs than the declared count. Writers pad with zero limbs; readers accept them. This makes each value's wire representation under a given declared count unique.
- The sign-and-limbs limb itself is not counted in the `Limb count`. A Natural with `Limb count = 4` occupies `1 + 4 = 5` limbs total.

Per-type specifics:

- **Natural** (`0x0005`): sign MUST be non-negative. Zero is represented with `limb count = 0` and no value limbs.
- **Integer** (`0x0006`): sign MAY be positive or negative. Negative zero is invalid (`sign = -1` with `limb count = 0` MUST be rejected). Zero is represented with `limb count = 0` and no value limbs.
- **Rational** (`0x0007`): `Limb count` MUST be even and MUST be at least 2. The first half of the value limbs hold the numerator (LSB-first); the second half hold the denominator (LSB-first). The sign applies to the rational as a whole. The denominator MUST NOT be zero.
  - **Reduction is not part of the wire format.** Both `1/2` and `2/4` are valid encodings of the same value. Whether a field requires reduction is a semantic constraint declared by the dialect author (Section 7.6.2).

## 7. Interface definition dialect

To create and share a new ISBF dialect, an author writes an **interface description file**: an ISBF message whose dialect MB is `[0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00]` and whose dialect version is `1`.

### 7.1 File structure

An interface description file is a valid ISBF message:

- **Header**: magic `['I','S','B','F']`, ISBF version `1`, dialect MB `[0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00]`, dialect version `1`.
- **Data section**: a single `dialect` object (ID `0x0100`).

The `dialect` object *is* the entire content of the data section. There is no other field, wrapper, or sibling. This follows directly from the single-main-field rule (Section 4.2).

This standalone form (header + `dialect` object) is distinct from the embedded preamble used by self-describing non-definition files. In the standalone form, the all-zeros dialect MB in the header marks the file as an interface definition file, and the `dialect` object follows directly in the data section. When the same `dialect` object is embedded inside another ISBF message (Section 6.3), it is wrapped in a `0x0001` field and carries no separate header; the outer message's header identifies the dialect.

**Computing the dialect object's size.** The dialect object's slot size is derivable from its own contents:

- The dialect name has a length prefix.
- The version is fixed at 2 bytes.
- The array of definitions (7.3) is a flexible array; its slot size is determined by the sum of its definitions, each of which has a self-describing size based on its alternative.

The parser reads the dialect object's fields in order. Once it finishes the array of definitions, it knows the object's total size; the file termination limb immediately follows, marking the end of the message. No scan to end-of-file is required.

### 7.2 The `dialect` object (ID `0x0100`, Object class)

| **Field name**       | **Type**                                            | **Required** |
| -------------------- | --------------------------------------------------- | ------------ |
| Dialect's name       | UTF-8 string (`0x0003`)                             | Yes          |
| Dialect's version    | Unsigned 16-bit (`0x0009`)                          | Yes          |
| Array of definitions | Flexible array of `definition` variants (`0x0101`)  | Yes          |

The dialect name feeds the header's dialect MB derivation (Section 4.1). The dialect version is copied into the header by the writer and verified by the parser.

### 7.3 Array of definitions (ID `0x0101`, flexible array)

A flexible array of up to **`0xFFFFFFFFFFFFFFFF`** (`2⁶⁴ − 1`) definitions, each containing a `definition` variant (ID `0x0102`). The `Size` section records how many definitions are actually used (0 to `2⁶⁴ − 1`; a zero-entry file declares no types and is valid but useless).

Definitions may appear in any order. Forward references are permitted; see 7.7 for resolution rules.

The `0xFFFFFFFFFFFFFFFF` maximum is the format-level cap for this specific field, chosen to match the `uint64` width of every array's `Size` section. It is not the same as a user-declared array's `Max elements` field (7.4.2), which the dialect author sets to any `uint64` value. The dialect object's array of definitions is a built-in field of the interface definition dialect; its maximum is fixed by this specification.

In practice the theoretical maximum is unreachable: every definition consumes at least one slot of the definitions array, and each slot's size is bounded by the largest `definition` alternative. A file with even thousands of definitions will far exceed the default 1 MB embedded-dialect size limit (Section 9.4). The `0xFFFFFFFFFFFFFFFF` cap exists to give the field a consistent width with all other array `Size` sections, not to suggest that real dialects will approach it.

### 7.4 Definition alternatives (ID `0x0102`, Variant class)

The `definition` variant has five alternatives:

| Alternative          | Type ID | Class  |
| -------------------- | ------- | ------ |
| Comment              | `0x0103`| Object |
| Array definition     | `0x0104`| Object |
| Bitfield definition  | `0x0105`| Object |
| Object definition    | `0x0106`| Object |
| Variant definition   | `0x0107`| Object |

Every non-comment definition declares a new type. The new type's ID and name are declared inside the definition, so other fields in the same file can reference it (see 7.7).

#### 7.4.1 Comment (ID `0x0103`, Object class)

| **Field name** | **Type**                | **Required** |
| -------------- | ----------------------- | ------------ |
| Text           | UTF-8 string (`0x0003`) | Yes          |

A comment carries documentation text. It is not a type declaration; it cannot be referenced.

#### 7.4.2 Array definition (ID `0x0104`, Object class)

Declares a new array type. Since an array has exactly one element type, the definition carries a single `field` variant rather than a `fields` array.

| **Field name** | **Type**                                              | **Required** |
| -------------- | ----------------------------------------------------- | ------------ |
| Type ID        | Unsigned 16-bit (`0x0009`), range `0x0100`–`0xFFFD`   | Yes          |
| Type name      | UTF-8 string (`0x0003`)                               | No           |
| Max elements   | Unsigned 64-bit (`0x000B`)                            | Yes          |
| Element type   | Single `field` variant (`0x0109`, see 7.6)            | Yes          |

Type IDs MUST be unique across the file; see 7.7.

The array's slot size is `Max elements × (element slot size)`. The `Element type` field is one `0x0109` instance, not an array; no wrapper type exists for "a single field variant" because the field variant itself is that type.

`Max elements` is a `uint64`, matching the width of the array's own `Size` section (Section 5.9). The declared maximum is a validation bound on the number of elements the array can ever hold. Dialect authors choosing `Max elements` for a fixed-size array should keep it modest — a `uint64` maximum implies a theoretical slot of up to `2⁶⁴ − 1` elements, which would exceed any practical file size. For nested (fixed-size) arrays, the actual slot pre-allocation is `Max elements × element slot size`, so a large declared maximum directly inflates every containing object's slot. Parsers bound this risk through the allocation budget required by Section 9.5.

At instantiation, an array declared with `Max elements = N` behaves as a fixed-size array in almost all cases. It behaves as a flexible-size array only when it is the *last field* of the *top-level object* (its slot grows with the number of used elements, up to N). In every other position, its slot is pre-allocated to N elements. See Section 5.9.

#### 7.4.3 Bitfield definition (ID `0x0105`, Object class)

Declares a new bitfield type.

| **Field name** | **Type**                                              | **Required** |
| -------------- | ----------------------------------------------------- | ------------ |
| Type ID        | Unsigned 16-bit (`0x0009`), range `0x0100`–`0xFFFD`   | Yes          |
| Type name      | UTF-8 string (`0x0003`)                               | No           |
| Subfields      | Subfields array (`0x010A`, see 7.5.2)                 | Yes          |

Type IDs MUST be unique across the file; see 7.7.

**Validation rules**:

- The Subfields array contains only `bitfield-subfield` variant instances (ID `0x010B`). No other field kind can appear by construction.
- The bitfield's limb count is `ceil(sum(subfield widths) / 16)`.
- The sum of subfield widths MUST NOT exceed `limb count × 16`. Trailing bits are implicit padding: not addressable, not constrained, ignored.
- The sum of subfield widths MUST be at least 1. An empty bitfield is invalid.

#### 7.4.4 Object definition (ID `0x0106`, Object class)

Declares a new object type.

| **Field name** | **Type**                                              | **Required** |
| -------------- | ----------------------------------------------------- | ------------ |
| Type ID        | Unsigned 16-bit (`0x0009`), range `0x0100`–`0xFFFD`   | Yes          |
| Type name      | UTF-8 string (`0x0003`)                               | No           |
| Fields         | Fields array (`0x0108`, see 7.5.1)                    | Yes          |

Type IDs MUST be unique across the file; see 7.7.

**Validation rules**:

- The object's slot size is `sum(field slot sizes)`. Fields are consecutive; no inter-field padding.
- Fields have **no field-level IDs**. Identity comes entirely from the field's position in the Fields array. Optional field names (see 7.6.1) are diagnostic labels only.
- Field names MAY be duplicated; the parser MUST NOT reject an object for duplicate names.

#### 7.4.5 Variant definition (ID `0x0107`, Object class)

Declares a new variant type: an allow-list of type IDs that any field of this variant may instantiate.

| **Field name**    | **Type**                                              | **Required** |
| ----------------- | ----------------------------------------------------- | ------------ |
| Type ID           | Unsigned 16-bit (`0x0009`), range `0x0100`–`0xFFFD`   | Yes          |
| Type name         | UTF-8 string (`0x0003`)                               | No           |
| Allowed type IDs  | Allowed type IDs array (`0x010C`, see 7.5.3)          | Yes          |

Type IDs MUST be unique across the file; see 7.7.

**Validation rules**:

- Every entry MUST resolve to a built-in type (`0x0001`–`0x0011`) or a dialect-declared type (`0x0100`–`0xFFFD`). Entries `0x0000`, `0xFFFE`, `0xFFFF`, `0x0012` are invalid: the first three are not types; `0x0012` is a field mechanism, not an instantiable type.
- The array MUST contain at least one entry.
- Direct self-reference is prohibited; recursion through a composite (e.g., an array of the variant's own type) is permitted. See 7.7.
- The variant's slot size is the maximum of its allowed types' slot sizes, computed after reference resolution.

### 7.5 Element arrays

The interface definition dialect uses three arrays, each with a maximum of 20 elements:

- Fields array (7.5.1) — used by Object definitions
- Subfields array (7.5.2) — used by Bitfield definitions
- Allowed type IDs array (7.5.3) — used by Variant definitions

The 20-element cap is deliberate: it encodes the same discipline the ISBF applies elsewhere — if a definition needs more than 20 entries, the correct fix is *composition*, not a larger array. Composition means declaring additional types and referencing them. There is no expressiveness lost; only verbosity gained, and the verbosity is the design prompt.

To save space in the schema definition, all three arrays are **flexible arrays** (elements are packed back-to-back, and the array's `Size` section gives the number of used elements). This allows variable-sized `field` variants to be stored without padding.

#### 7.5.1 Fields array (ID `0x0108`, flexible array)

Used by Object definitions. A flexible array of up to 20 slots, each containing a `field` variant (`0x0109`). The `Size` section gives the used count (1–20; 0 is degenerate and should be rejected). The field variant carries no field-level ID; the slot's position is the field's identity. Optional diagnostic names are permitted (7.6.1).

#### 7.5.2 Subfields array (ID `0x010A`, flexible array)

Used by Bitfield definitions. A flexible array of up to 20 slots, each containing a `bitfield-subfield` variant (`0x010B`). The `Size` section gives the used count (1–20; 0 is degenerate).

#### 7.5.3 Allowed type IDs array (ID `0x010C`, flexible array)

Used by Variant definitions. A flexible array of up to 20 slots, each containing a `uint16` type ID (`0x0009`). The `Size` section gives the used count (1–20; 0 is degenerate).

### 7.6 The `field` variant (ID `0x0109`, Variant class)

The `field` variant declares one field within an Object, Array, or Variant definition. Each alternative corresponds to a built-in type or to a dialect reference; the chosen alternative determines the payload that follows (the type-appropriate constraints, or the referenced type ID for `0x0012`).

The `field` variant is **variable-sized**: its total size is determined by its alternative ID.

| Alternative        | Type ID  | Valid context             | Total Size |
| ------------------ | -------- | ------------------------- | ---------- |
| ISBF dialect       | `0x0001` | Object / array            | 21 limbs   |
| BLOB               | `0x0002` | Object / array            | 29 limbs   |
| UTF-8 string       | `0x0003` | Object / array            | 70 limbs   |
| Boolean            | `0x0004` | Object / array            | 21 limbs   |
| Natural            | `0x0005` | Object / array            | 25 limbs   |
| Integer            | `0x0006` | Object / array            | 25 limbs   |
| Rational           | `0x0007` | Object / array            | 25 limbs   |
| Unsigned 8-bit     | `0x0008` | Object / array            | 34 limbs   |
| Unsigned 16-bit    | `0x0009` | Object / array            | 34 limbs   |
| Unsigned 32-bit    | `0x000A` | Object / array            | 34 limbs   |
| Unsigned 64-bit    | `0x000B` | Object / array            | 34 limbs   |
| Signed 8-bit       | `0x000C` | Object / array            | 34 limbs   |
| Signed 16-bit      | `0x000D` | Object / array            | 34 limbs   |
| Signed 32-bit      | `0x000E` | Object / array            | 34 limbs   |
| Signed 64-bit      | `0x000F` | Object / array            | 34 limbs   |
| Float32            | `0x0010` | Object / array            | 25 limbs   |
| Float64            | `0x0011` | Object / array            | 29 limbs   |
| Dialect reference  | `0x0012` | Object / array            | **2 limbs** |

The `bitfield-subfield` is not part of this variant; it lives in a separate variant type (`0x010B`) used exclusively by the Subfields array (7.5.2).

#### 7.6.1 Common field metadata

For every alternative **except `0x0012`**, the field variant begins with an optional diagnostic name container:

| Component  | Limbs | Content                                                |
| ---------- | ----- | ------------------------------------------------------ |
| Size       | 4     | `int64` following Section 5.5's container size rules:  |
|            |       | magnitude = byte count (0–32); sign = partial-limb flag |
| Name bytes | 16    | UTF-8 bytes, zero-padded to 16 limbs                   |

A Size of `0` means the name is empty. A Size of `1`–`32` gives the actual name length. A Size with magnitude > 32 is a parseable error (`0x0E`, name exceeds the fixed slot).

The name carries no semantic meaning. It is used for diagnostics, error messages, and tooling. It is not used to identify or order fields, and field names may be duplicated within an object; the parser MUST NOT reject an object on that basis.

#### 7.6.2 Constraint payload by alternative

After the alternative ID (and the name container, where applicable), the constraint payload follows. All constraint fields are fixed-size and always present for the given alternative; those the dialect author did not specify carry their defaults. Padding limbs MUST be zeroed.

**`0x0001` (ISBF dialect)** — 0 real limbs (Total 21 limbs: 1 ID + 20 Name).

**`0x0002` (BLOB)** — 8 real limbs (Total 29 limbs):

| Limbs | Field    | Type                | Default |
| ----- | -------- | ------------------- | ------- |
| 0–3   | Min size | `uint64`            | 0       |
| 4–7   | Max size | `uint64` (required) | —       |

**`0x0003` (UTF-8 string)** — 49 real limbs (Total 70 limbs):

| Limbs  | Field         | Type                                | Default |
| ------ | ------------- | ----------------------------------- | ------- |
| 0–3    | Min size      | `uint64`                            | 0       |
| 4–7    | Max size      | `uint64` (required)                 | —       |
| 8      | Range count   | `uint16` (0–10)                     | 0       |
| 9–48   | Ranges        | 10 × `{start: uint32, end: uint32}` | zeroed  |

Ranges beyond the range count are zeroed. A range count > 10 is a dialect error (`0x0B`).

**`0x0004` (Boolean)** — 0 real limbs (Total 21 limbs).

**`0x0005` (Natural)** — 4 real limbs (Total 25 limbs):

| Limbs | Field                | Type                                  | Default |
| ----- | -------------------- | ------------------------------------- | ------- |
| 0     | Limb count           | `uint16` (required)                   | —       |
| 1     | Min value power-of-ten | `uint16`                            | 0       |
| 2     | Parity               | `uint16` (0=any, 1=even, 2=odd)       | 0       |
| 3     | Must be reduced      | `uint16` (0=no; invalid, must be 0)   | 0       |

**`0x0006` (Integer)** — 4 real limbs (Total 25 limbs). Same layout as `0x0005`.

**`0x0007` (Rational)** — 4 real limbs (Total 25 limbs). Same layout as `0x0005`, except `Must be reduced` may be `0` or `1`.

**`0x0008`–`0x000F` (fixed-width integers)** — 13 real limbs (Total 34 limbs):

| Limbs | Field       | Type                                          | Default |
| ----- | ----------- | --------------------------------------------- | ------- |
| 0–3   | Min value   | `int64` (signed) or `uint64` (unsigned)       | 0 / type min |
| 4–7   | Max value   | `int64` (signed) or `uint64` (unsigned)       | 0 / type max |
| 8     | Parity      | `uint16` (0=any, 1=even, 2=odd)               | 0       |
| 9–12  | Multiple of | `uint64`                                      | 0 (no constraint) |

For unsigned types, "type min" is 0 and "type max" is `2^N − 1`. For signed types, they are `−2^(N−1)` and `2^(N−1) − 1`. The defaults express "no constraint," which is semantically equivalent to the type's natural bounds.

**`0x0010` (Float32)** — 4 real limbs (Total 25 limbs):

| Limbs | Field     | Type      | Default |
| ----- | --------- | --------- | ------- |
| 0–1   | Min value | `float32` | −INF    |
| 2–3   | Max value | `float32` | +INF    |

**`0x0011` (Float64)** — 8 real limbs (Total 29 limbs):

| Limbs | Field     | Type      | Default |
| ----- | --------- | --------- | ------- |
| 0–3   | Min value | `float64` | −INF    |
| 4–7   | Max value | `float64` | +INF    |

**`0x0012` (dialect reference)** — 1 real limb (Total 2 limbs):

| Limbs | Field   | Type      | Default |
| ----- | ------- | --------- | ------- |
| 0     | Type ID | `uint16`  | —       |

The `0x0012` alternative is the sole exception: it carries no name container and no constraint payload. Its structure is exactly 2 limbs: 1 limb for the alternative ID (`0x0012`) and 1 limb for the referenced Type ID. The referenced Type ID MUST be in `0x0100`–`0xFFFD` and MUST resolve to a declared type in the same file. See 7.6.4 for resolution rules.

#### 7.6.3 The `bitfield-subfield` variant (ID `0x010B`, Variant class)

The `bitfield-subfield` variant declares one subfield within a Bitfield definition. It is used exclusively as the element type of the Subfields array (7.5.2). The variant exists so new subfield kinds can be added in future revisions without changing the Subfields array's structure or existing alternatives.

Today, exactly one alternative is defined:

| Alternative                 | Type ID  | Class  |
| --------------------------- | -------- | ------ |
| Standard bitfield subfield  | `0x010D` | Object |

A slot with any other alternative ID is a hard error (`0x0B`).

The `bitfield-subfield` variant is variable-sized. The `0x010D` alternative has the following wire layout:

| Component      | Limbs | Content                              |
| -------------- | ----- | ------------------------------------ |
| Name container | 20    | Optional diagnostic name (empty=20)  |
| Width          | 1     | `uint8` (1–15)                       |

Total size: **22 limbs** (1 ID limb + 20 Name limbs + 1 Width limb).

The name container follows the same wire layout as the field variant's name container (Section 7.6.1): 4 limbs for `int64` size, 16 for name bytes, zero-padded. The `Width` field is a single `uint8` in the lower byte of the last limb; the upper byte is zeroed.

##### 7.6.3.1 Standard bitfield subfield (ID `0x010D`, Object class)

| Field name | Type                       | Required             |
| ---------- | -------------------------- | -------------------- |
| Field name | UTF-8 string (`0x0003`)    | No (for diagnostics) |
| Width      | Unsigned 8-bit (`0x0008`)  | Yes; MUST be 1–15    |

**Validation rules**:

- Width in `[1, 15]`. Width 0 is invalid.
- Packing follows Section 3.1 (LSB-first, subfield order matches declaration order).
- The sum of all widths is the bitfield's logical width; limb count is `ceil(sum / 16)`; trailing bits are implicit padding.
- Subfield value constraints (e.g., "≤ 5") are NOT expressed here. A subfield's value space is `[0, 2^width - 1]`. Callers that need tighter bounds declare the bitfield as an object field and apply the constraint at the object-field level (7.6.2).

#### 7.6.4 The `dialect-reference` type (ID `0x0012`)

A field whose type is one of the dialect-declared types declared in the same file. It is an atomic type: its payload is a single `uint16` type ID.

| Payload | Type                       | Required                                                    |
| ------- | -------------------------- | ----------------------------------------------------------- |
| Type ID | Unsigned 16-bit (`0x0009`) | Yes; in `0x0100`–`0xFFFD`; MUST resolve to a declared type  |

References to built-in types (`0x0001`–`0x0011`) are invalid here; use the corresponding field-variant alternative. References to `0x0000`, `0xFFFE`, `0xFFFF`, `0x0012` are invalid. Constraints on the referenced type are declared at the referenced type's definition, not here.

### 7.7 Reference resolution

A `dialect-reference` may reference a type declared later in the same file (forward reference). The parser MUST:

1. Read all definitions in the array of definitions.
2. Collect every declared type ID and kind.
3. **Reject immediately if any type ID is duplicated** (error `0x0B`). Type IDs are the sole referent fields use, so ambiguity is fatal.
4. Resolve every field variant whose alternative is `0x0012`: verify its payload type ID corresponds to a declared type.
5. Resolve every entry in every Variant's allowed type IDs array (`0x010C`).
6. Reject if any reference is unresolved (error `0x0B`).

Self-references are prohibited, whether direct or transitive. The parser MUST detect cycles in the reference graph and reject with the appropriate hard error (see Section 9).

### 7.8 Example (informational)

A minimal dialect declaring a `Person` object with two fields (`name` of type UTF-8 string, `age` of type UInt8). After the 16-byte header, the data section contains one `dialect` object (`0x0100`):

- Name: `io.intrashell.example.person`
- Version: `1`
- Array of definitions, one entry: an `Object definition` (`0x0106`)
  - Type ID: `0x0100`
  - Type name: `Person`
  - Fields array, 2 slots used:
    - Field 0: name `name`, type `0x0003` (UTF-8 string), max size `64`, min size `0`
    - Field 1: name `age`, type `0x0008` (UInt8), max value `255`

Fields are identified by position (field 0 is `name`, field 1 is `age`); the names are diagnostic labels only, not identity.

The dialect MB is the first 8 bytes of `SHA-256("io.intrashell.example.person")`.

At instantiation, a `Person` occupies a slot of `64 + 1 = 65` limbs, with field 0 at the first 64 limbs and field 1 at limb 65.

### 7.9 Reserved IDs within the interface definition dialect

The interface definition dialect assigns IDs `0x0100` through `0x010D` to its own constructs:

| ID       | Construct                          |
| -------- | ---------------------------------- |
| `0x0100` | `dialect` object                   |
| `0x0101` | Array of definitions               |
| `0x0102` | `definition` variant               |
| `0x0103` | Comment                            |
| `0x0104` | Array definition                   |
| `0x0105` | Bitfield definition                |
| `0x0106` | Object definition                  |
| `0x0107` | Variant definition                 |
| `0x0108` | Fields array                       |
| `0x0109` | `field` variant                    |
| `0x010A` | Subfields array                    |
| `0x010B` | `bitfield-subfield` variant        |
| `0x010C` | Allowed type IDs array             |
| `0x010D` | Standard bitfield subfield object  |

These IDs are reserved *within the interface definition dialect*. They do not constrain user dialects, which have their own ID space. A user dialect declaring a type with ID `0x0100` is declaring its own type, unrelated to the dialect object.

## 8. Error handling and trace events

The parser reports its state through 8-bit codes. These fall into four categories by what they report and what the parser does when it emits one:

- **Success** — the terminal state after a clean parse.
- **Trace events** — informational; emitted only when tracing is enabled; never returned as errors.
- **Hard errors** — parse failures that prevent further parsing; always returned; parsing stops immediately.
- **Parseable errors** — parse failures that permit continued parsing; the application may inspect the partial result and decide whether to abort, log, or recover.

The distinction matters: a trace event and a parseable error can appear in the same run (e.g., "atomic field found" is a trace event, "atomic value invalid" is a parseable error), while a hard error terminates the run.

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

Error codes are stable across ISBF revisions. New codes may be added at `0x26` and above; existing codes will not be reassigned. Implementations may add codes at `0x80` and above for their own diagnostics, provided those codes are documented as implementation-specific.

## 9. Security

### 9.1 Integer overflow in field size

A parser MUST reject messages in which any field's `Size` section exceeds the bounds of the field, for every class. On failure, emit the pertinent code:

- `0x11` for containers
- `0x1C` for arrays

### 9.2 Recursive object definitions

A parser MUST reject dialect definitions in which fields at the same taxonomical level nest each other. Each field must be a parent, child, or sibling — never more than one of these. On failure, emit:

- `0x08` for embedded dialects
- `0x0B` for pre-shared dialects

### 9.3 Dialect magic byte collision

Dialect MBs are derived by truncating SHA-256 to 64 bits. A collision would allow a malicious packet to rewrite a dialect's definition. Parsers MUST offer these modes when reading ISBF files:

- Open with pre-shared dialect, ignore embedded dialects (default).
- Open and parse with the embedded dialect (if present).
- Open and ignore any dialect definition (inspection mode).

### 9.4 Embedded interface definition size limit

Parsers MUST allow the caller to specify a size limit for embedded dialects at the point of each parse call. The limit bounds how many bytes the parser will read from a `0x0001` preamble (Section 6.3) before rejecting it. The default limit is **1 MB**; callers MAY pass a different limit — larger for trusted inputs, smaller for adversarial or resource-constrained contexts — on a per-call basis.

The limit is a per-call parameter, not a parser-wide configuration. A single parser instance can parse a large trusted dialect under one call and a small untrusted one under another, with different limits, without reconfiguration.

A preamble whose byte length exceeds the caller-supplied limit MUST be rejected with a hard error (`0x09`, dialect beyond size constraint). The parser MUST check the length before parsing the embedded dialect, not after.

### 9.5 Fixed-size array allocation bounds

Fixed-size arrays (Section 5.9) pre-allocate their slot as `Max elements × element slot size` limbs. When the array is nested inside an object (or selected by a variant, or otherwise declared as fixed-size), this slot is materialized as part of the containing object's allocation, before any element is written. Variants carry the same risk: their slot is sized to the largest allowed alternative, so a variant over a large fixed-size array inherits its potential allocation.

A malicious dialect could declare a fixed-size array with an enormous `Max elements` (up to `2⁶⁴ − 1`, per Section 7.4.2) and a minimal element size (for example, one limb per element). Such a dialect is a few hundred bytes on disk but, when instantiated, demands terabytes of allocation before the parser can begin reading any actual data. This is a decompression-bomb-class attack: the payload is small, the resource cost is unbounded.

To prevent it, parsers MUST accept an **allocation budget** as a per-call parameter, alongside the embedded-dialect size limit (Section 9.4). The budget is the maximum total number of bytes the parser will allocate during a single parse call, across all objects, arrays, variants, buffers, and internal parser state.

The parser MUST compute an object's total allocated size from the dialect declaration before initializing it, by summing:

- Every field's slot size within the object, recursively for nested objects.
- For each fixed-size array, `Max elements × element slot size`.
- For each variant, the maximum of its allowed alternatives' slot sizes.

If the cumulative allocation — the object being initialized plus everything already allocated in the same parse call — would exceed the budget, the parser MUST stop parsing and return a hard error (`0x25`, "Allocation budget exceeded"). The check is a pre-flight computation, not a post-allocation detection: the parser does not attempt the allocation and then fail; it computes the required size and rejects before touching the allocator.

Callers set the budget per call, so a single parser instance can parse a large trusted dialect under a generous budget and a small untrusted one under a tight budget. The default budget is the embedded-dialect size limit (Section 9.4, default 1 MB); callers MAY supply a different value per call. The budget applies to the outer message's allocation as well as to any embedded preamble.

For zero-copy parsers that do not allocate (they read directly from a memory-mapped file), the budget still applies as a **bounds check** on the total slot size the parser will traverse: if the sum of fixed-size slots the parser is about to walk exceeds the budget, it stops, even though it would not have allocated that memory. This prevents a malicious file from forcing the parser to walk through gigabytes of address space looking for a field it cannot find.

### 9.6 File termination inside variants

The file termination ID MUST NOT be written inside a variant's list of allowed values. If a parser finds `0xFFFF` within a variant field, it MUST emit `0x20`.

## 10. Notes

### 10.1 Versioning of ISBF and its dialects

Formats are updated far less often than programs. Full semantic versioning is unnecessary. The version format is `Major.Revision`, where `Major` indicates the actual format and `Revision` is for the version of this document that describes it. Only `Major` matters to a parser, and only `Major` appears in the header.

### 10.2 Design rationale

ISBF was born out of the need to share one format across data stores and communications protocols. Once paging, block allocation, and framing are in place, those two use cases diverge; the best way to serve both was to target that shared layer. ISBF therefore became a block-level metaformat: a substrate on which developers write their own dialects and solutions. In this sense, ISBF is:

- **A block allocator for files and packets.** It reasons in whole blocks of memory, not single fields like a scratch allocator.
- **Below SQLite.** SQLite provides paging, B-Trees, and a metadata table that tracks records and unallocated slots. ISBF provides only the paging, leaving the developer to choose paradigms and techniques for the layers above: LSM-Trees, SST, shadow paging, WAL, rollback journals, or any combination.
- **Above ASN.1.** ASN.1 covers only the encoding of data structures. ISBF provides said structures by default and lets the developer skip straight to defining their packet layout, semantic constraints, and message shapes.

ISBF therefore enables building databases, data stores, filesystems, application formats, and communication protocols from first principles, without reinventing block allocation, page recovery, or endianness handling — while leaving every architectural choice above the block layer to the developer. It is consequently not a replacement for SQLite, ASN.1, CBOR, Thrift, or Avro, which provide abstractions above the block layer. WAL, shadow paging, SSTs, and LSM-Trees are above the block layer and must be built on top of ISBF, not provided by it.

### 10.3 Concurrency

The WIP ID signals that a slot is being written, but it is not nanosecond-atomic at the CPU level. A lock-free structure tracking currently-written slots MUST be implemented in the parser. One implementation is a lock-free circular list of in-flight slots.

Append operations are strictly sequential. The writer MUST enforce this with a lock or equivalent mechanism.

### 10.4 ACID support

ISBF provides built-in handling for data corruption and write concurrency, but does not support atomicity, consistency, isolation, or durability. Those features depend on the specific dialect, which must supply, for example:

- An internal metadata table referencing current records.
- An internal WIP type for appending new versions of records.
- An update mechanism that changes metadata-table references from current records to updated ones.

Other approaches are valid. The principle is the same: ACID support belongs to the ISBF dialect and the system that parses it, not to the format itself.

### 10.5 Zero-copy design

ISBF is designed to support zero-copy access to field values whenever possible. Fixed slots and fixed-width elements mean that a parser reading a memory-mapped file can access a field's value by computing its offset and casting the pointer — no deserialization, no copies, no offset tables.

This goal drives several design choices:

- **Fixed slots, not variable-length records.** Every field occupies a known, dialect-declared number of limbs.
- **Fixed-width built-in types** (`uint8` through `float64`). Their memory representation is identical to their wire representation on a little-endian machine, so a memory-mapped read yields the value directly.
- **16-bit limb alignment.** Every field's start address is 2-byte aligned, sufficient for all fixed-width types up to 16 bits and compatible with memcpy-based access for wider types.
- **Container size as an `int64`.** A container's used length can be read as a single 8-byte value, without parsing an arbitrary-precision integer.

Bitfields are the deliberate exception. Subfields share a limb, so extracting a subfield requires a mask-and-shift, not a direct read. Bitfields are provided for compactness, not for zero-copy access; callers that need in-place access should use atomic fields and accept the space cost.

Variable-length strings and BLOBs are stored as fixed-slot containers with an `int64` used-length prefix (Section 5.5). The bytes of the string or BLOB beyond the used length are padding and are ignored. This gives zero-copy access to the used portion (a pointer and a length), at the cost of padding in the unused portion.

Flexible-size arrays (Section 5.9), which occur only as the last field of the top-level object, grow and shrink with their used elements. Zero-copy access to a specific element is valid at any given moment, but the element's offset may change after a modification (since the file's size changes). Programs that hold references to elements across modifications must re-parse after mutation; programs that read once and release can use zero-copy access freely.
