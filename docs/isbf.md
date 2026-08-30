# Binary Serialization Format Specification

## 1. Overview & Core Design Principles

This specification defines a high-performance, byte-aligned binary serialization format designed for databases, network protocols, entity-component systems (ECS), and file storage.

* **Byte Alignment:** All primitive data types and container lengths align to full bytes. Mid-byte nibble splitting for raw values is prohibited to optimize vector processing, hardware byte-swapping (`bswap`), and CPU cache alignment.
* **Header-First Architecture:** Metadata, schema definitions, and dictionary tables precede raw payload data, allowing parsing without runtime type-tag overhead for schema-bound data.
* **Dual-Tier Schema Model:** Built-in application structures (**Compile-Time Schemas**) are strictly separated from user-defined dynamic structures (**Runtime Schemas**) to prevent collision, corruption, or dynamic overriding of core engine layouts.
* **Separation of Structure and Reflection:** Field types and structural layouts are defined independently from human-readable names and debugging labels, reducing binary footprint and protecting layout integrity during stream updates.

---

## 2. Global Type Matrix (High Nibble Encoding)

Every serialized item begins with a **1-byte Tag Byte**. The high nibble (bits 7–4) designates the **Type ID**, while the low nibble (bits 3–0) provides type-specific parameter or size metadata.

       Bit 7   Bit 6   Bit 5   Bit 4   Bit 3   Bit 2   Bit 1   Bit 0
     +-------+-------+-------+-------+-------+-------+-------+-------+
     |         High Nibble           |          Low Nibble           |
     |          (Type ID)            |       (Type Parameter)        |
     +-------+-------+-------+-------+-------+-------+-------+-------+

| Type ID (Hex) | Category | Low Nibble Meaning | Payload Bytes |
| :--- | :--- | :--- | :--- |
| **`0x0`** | Metadata | Metadata Subtype ($0$–$F$) | Dependent on Subtype |
| **`0x1`** | Signed Int | Size exponent ($2^N$ bytes: `0`=1B, `1`=2B, `2`=4B, `3`=8B) | $1, 2, 4,$ or $8$ bytes |
| **`0x2`** | Unsigned Int | Size exponent ($2^N$ bytes: `0`=1B, `1`=2B, `2`=4B, `3`=8B) | $1, 2, 4,$ or $8$ bytes |
| **`0x3`** | Float | IEEE Size Code (`0`=F32, `1`=F64, `2`=F16, `3`=F128) | $2, 4, 8,$ or $16$ bytes |
| **`0x4`** | Bool | Direct Value (`0` = `false`, `1` = `true`) | **0 bytes** |
| **`0x5`** | Bitset / Bool Set | Count of boolean flags ($1$–$16$) | $\lceil N / 8 \rceil$ bytes ($1$ or $2$ bytes) |
| **`0x6`** | String (UTF-8) | Embedded `Type 2` size code ($0$–$3$) | Length bytes + UTF-8 payload |
| **`0x7`** | BLOB | Embedded `Type 2` size code ($0$–$3$) | Length bytes + Raw binary payload |
| **`0x8`** | Array | Embedded `Type 2` size code ($0$–$3$) | Length bytes + **Element Tag** + Payloads |
| **`0x9`** | Associative Array | Embedded `Type 2` size code ($0$–$3$) | Length bytes + **Key Tag** + **Value Tag** + Payloads |
| **`0xA`** | Dynamic Struct | Embedded `Type 2` size code ($0$–$3$) | Field Count bytes + Tagged Fields |
| **`0xB`** | Compile-Time Schema | Schema ID Sequence | **Raw untagged field data** |
| **`0xC`** | Runtime Schema | Schema ID Sequence | **Raw untagged field data** |
| **`0xD`** | Compile-Time Offset | Target Compile-Time Schema ID Sequence | **8 bytes** (`UInt64`) address offset |
| **`0xE`** | Runtime Offset | Target Runtime Schema ID Sequence | **8 bytes** (`UInt64`) address offset |
| **`0xF`** | Padding | Must be `0xF` (`0xFF` total tag byte) | **0 bytes** (Parser skip marker) |

---

## 3. Detailed Data Layout Definitions

### 3.1 Numeric Primitives (`0x1`, `0x2`, `0x3`)
Integers and floating-point values write raw binary values immediately following the tag byte. Byte order is governed by the stream's Byte Order Mark (BOM).

* **Signed Int (`0x1`) & Unsigned Int (`0x2`):**
  * `0x10` / `0x20` $\rightarrow$ 1 byte (`Int8` / `UInt8`)
  * `0x11` / `0x21` $\rightarrow$ 2 bytes (`Int16` / `UInt16`)
  * `0x12` / `0x22` $\rightarrow$ 4 bytes (`Int32` / `UInt32`)
  * `0x13` / `0x23` $\rightarrow$ 8 bytes (`Int64` / `UInt64`)

* **Float (`0x3`):**
  * `0x30` $\rightarrow$ IEEE 754 Binary32 (4 bytes)
  * `0x31` $\rightarrow$ IEEE 754 Binary64 (8 bytes)
  * `0x32` $\rightarrow$ IEEE 754 Binary16 / `bfloat16` (2 bytes)
  * `0x33` $\rightarrow$ IEEE 754 Binary128 Quad Precision (16 bytes)

### 3.2 Containers (`0x6`, `0x7`, `0x8`, `0x9`, `0xA`)
Containers store their payload length using an embedded `Type 2` size indicator inside the tag byte's low nibble ($0 \rightarrow \text{UInt8}$, $1 \rightarrow \text{UInt16}$, $2 \rightarrow \text{UInt32}$, $3 \rightarrow \text{UInt64}$).

* **String (`0x6`) & BLOB (`0x7`):**
  `[Tag Byte] -> [Length: Type 2 UInt] -> [Raw Bytes Payload]`

* **Array (`0x8`):** Arrays define a single element tag up-front to eliminate per-item tag overhead.
  `[Tag Byte] -> [Element Count: Type 2 UInt] -> [Element Type Tag Byte] -> [Value 1] ... [Value N]`

* **Associative Array (`0x9`):** Key and value types are declared at the array header.
  `[Tag Byte] -> [Pair Count: Type 2 UInt] -> [Key Type Tag Byte] -> [Value Type Tag Byte] -> [K1, V1, K2, V2, ...]`

* **Dynamic Object / Struct (`0xA`):** Used strictly in schemaless contexts. Every field carries its own explicit type tag.
  `[Tag Byte] -> [Field Count: Type 2 UInt] -> [Tagged Field 1] ... [Tagged Field N]`

---

## 4. Schema Composition & Resolution (`0xB`, `0xC`, `0xD`, `0xE`)

Schema IDs use a hierarchical composition model to permit over 1,000,000 distinct schemas while maintaining byte alignment.

### 4.1 Schema ID Resolution Rules
1. **Level 0 (Root):** Stored inside the low nibble of the Schema/Offset Tag Byte ($0x0$–$0xF$).
2. **Levels 1 & 2:** If the root schema defines child sub-schemas, the parser reads the next **1 byte** as a `UInt8` ($0$–$255$).
3. **Levels 3 & 4:** If further levels exist, the parser reads an additional **1 byte** as a `UInt8` ($0$–$255$).

Sub-schema lookup depths are deterministic and locked at compile-time/registration time. The parser never reads dynamic varints or bit-continuation flags during schema resolution.

### 4.2 Schema Instance Layout (`0xB` and `0xC`)
Payloads tagged with `0xB` (Compile-Time) or `0xC` (Runtime) omit field tags entirely. Values are written sequentially according to the structural definition registered in the metadata headers.

`[Tag Byte: 0xB_ or 0xC_] -> [Optional Level 1/2 Byte] -> [Optional Level 3/4 Byte] -> [Field 1 Value] [Field 2 Value] ...`

### 4.3 Type-Safe Offsets (`0xD` and `0xE`)
Offsets provide zero-copy memory mapping across files and network buffers.
* `0xD` **(Compile-Time Offset):** Must target a location containing a `Type B` instance matching the specified Schema ID.
* `0xE` **(Runtime Offset):** Must target a location containing a `Type C` instance matching the specified Schema ID.

`[Tag Byte: 0xD_ or 0xE_] -> [Schema ID Sequence] -> [Address: 8-Byte UInt64]`

---

## 5. Metadata Subsystem (`Type 0`)

Metadata blocks establish stream parameters, version information, and dynamic structural contracts.

### 5.1 Metadata Subtypes Table

| Subtype (Hex) | Name | Scope | Structure / Payload |
| :--- | :--- | :--- | :--- |
| **`0x0`** | BOM / Endian Check | System | 2-byte sequence `0x01FF` |
| **`0x1`** | Application Magic Marker | System | `Type 6` String / `Type 7` BLOB format key |
| **`0x2`** | Application Version | System | `Type 8` Array of `Type 2` UInts (`Major`, `Minor`, `Patch`) |
| **`0x3`** | Compile-Time Schema Names | Compile-Time | `Type 9` Map: `Schema ID Sequence` $\rightarrow$ `Type 6 String` |
| **`0x4`** | Compile-Time Field Names | Compile-Time | `Type 9` Map: `(Schema ID + Field Index)` $\rightarrow$ `Type 6 String` |
| **`0x5`** | Compile-Time Layouts | Compile-Time | Structural definitions for static application types |
| **`0x6`** | Runtime Schema Names | Runtime | `Type 9` Map: `Schema ID Sequence` $\rightarrow$ `Type 6 String` |
| **`0x7`** | Runtime Field Names | Runtime | `Type 9` Map: `(Schema ID + Field Index)` $\rightarrow$ `Type 6 String` |
| **`0x8`** | Runtime Layouts | Runtime | Structural definitions for dynamic user types |
| **`0x9`** | Runtime Version Relation | Runtime | Maps `New Runtime Schema ID` $\rightarrow$ `Parent Schema ID` + `Version UInt` |
| **`0xA`–`0xF`** | Reserved | System | Reserved for protocol extensions |

### 5.2 Schema Layout Definition Structure (`0x5` and `0x8`)
Structural layout definitions register field ordering for untagged schema payloads:

$$\text{Definition Layout}: [\text{Tag: } 0x05 \text{ or } 0x08] \rightarrow [\text{Schema ID Sequence}] \rightarrow [\text{Field Count: Type 2 UInt}] \rightarrow [\text{Field 1 Type Tag}] \dots [\text{Field N Type Tag}]$$

### 5.3 Schema Mutability & Error Handling
1. **Compile-Time Immutability:** Subtypes `0x3`, `0x4`, and `0x5` must be fully established during initialization. Stream updates attempting to alter Compile-Time schemas must trigger an immediate `ImmutableSchemaError`.
2. **Runtime Append-Only Contract:** Subtypes `0x6`, `0x7`, `0x8`, and `0x9` can be emitted dynamic mid-stream. Once a Runtime Schema ID layout is defined, its field types and order cannot be mutated.
3. **Schema Evolution (`0x9`):** Alterations to a runtime schema require defining a new Runtime Schema ID and registering a version relation entry (`0x9`) pointing to the parent Schema ID.

---

## 6. Complete Binary Example

The following byte sequence illustrates a complete header initialization followed by an array of a custom compile-time schema instance.

### Scenario
* **Compile-Time Schema ID:** `1` (Name: `"Transform"`, Fields: `Float32 X`, `Float32 Y`, `Float32 Z`)
* **Payload:** An array containing 2 `Transform` instances: `{1.0, 2.0, 3.0}` and `{4.0, 5.0, 6.0}`.

### Binary Byte Stream (Hex)

-- HEADER SECTION --
00 01 FF                ; Type 0, Subtype 0 (BOM) -> Bytes: 0x01, 0xFF (Little-Endian detected)
01 60 04 4D 59 41 50    ; Type 0, Subtype 1 (App Magic) -> Type 6 String "MYAP"
05 11 00 03 30 30 30    ; Type 0, Subtype 5 (Compile-Time Layout)
                        ; -> Schema ID 1, Field Count: 3, Types: 0x30 (F32), 0x30 (F32), 0x30 (F32)

-- DATA PAYLOAD SECTION --
80 02 B1                ; Type 8 Array (Size UInt8 = 2 items), Element Type: 0xB1 (Compile Schema ID 1)

; Instance 1 Payload (Raw Untagged Values)
00 00 80 3F             ; Float32 X = 1.0
00 00 00 40             ; Float32 Y = 2.0
00 00 40 40             ; Float32 Z = 3.0

; Instance 2 Payload (Raw Untagged Values)
00 00 80 40             ; Float32 X = 4.0
00 00 A0 40             ; Float32 Y = 5.0
00 00 C0 40             ; Float32 Z = 6.0
