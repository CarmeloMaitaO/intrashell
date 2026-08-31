# Intrashell Binary Format (ISBF) Specification

## File Identification & Characteristics

* **Endianness:** little-endian
* **File extension:** `isbf` / `ISBF`
* **MIME type:** `application/vnd.intrashell.isbf`
* **Magic bytes:** `0x46` `0x42` `0x53` `0x49` ("FBIS" or `1_230_193_222u32`)
* **Schema:** pre-shared or embeddded schema
* **Elements size in bits:** all elements use full octects with no splitting

## File Structure

| Order |               content            |
| ----  | -------------------------------- |
| 0     | Header                           |
| 1     | Schema (pre-shared or embedded)  |
| 2     | Data                             |

### Header Structure

| Offset (in octects) | size (in octects)|                 Content             |
| ------------------- | ---------------- | ----------------------------------- |
| 0                   | 4                | Magic bytes of the specification    |
| 4                   | 1                | Version of the ISBF specification   |
| 5                   | 4                | Magic bytes of the application      |
| 9                   | 1                | Version of the application          |
| 10                  | Dynamic          | Schema or data                      |

> The schema is tied to the Magic bytes and version of the application

### Schema Structure

* **Schemas define a list of structures**
* **Structures include tags inside**
* **Tags can be:**
  * **Structures:** dynamic length (not present in data / schema implementation)
  * **Primitives:** Fixed length
  * **Containers:** Fixed or dynamic length (depends on the definition)
  * **Special / Metadata:** Fixed or dynamic length (depends on the definition)

| Offset (in octects) | size (in octects)|                 Content             |
| ------------------- | ---------------- | ----------------------------------- |
| 0                   | 4                | Size of the schema in bytes         |
| 4                   | Dynamic          | List of definitions                 |

> Only structures can exist at the top-level of the schema

> "PS8" means _Payload Size in Octects_. It is followed by what it contains

> "TS8" means _Total Size in Octects_

#### Structure Tags

| Tag ID |     Name    | PS8: ID | PS8: # of tags inside     |  TS8  |
| ------ | ----------- | ------- | ------------------------- | ----- |
| `0x00` | Struct1     | 1       | 8                         | > 10  |
| `0x01` | Struct2     | 2       | 8                         | > 11  |

> The tag ID of structures is included in the data / schema implementation

#### Primitive Tags: Numeric

| Tag ID |     Name    | PS8: Number |  TS8  |
| ------ | ----------- | ----------- | ----- |
| `0x02` | Uint8       | 1           | 2     |
| `0x03` | Uint16      | 2           | 3     |
| `0x04` | Uint32      | 4           | 5     |
| `0x05` | Uint64      | 8           | 9     |
| `0x06` | Int8        | 1           | 2     |
| `0x07` | Int16       | 2           | 3     |
| `0x08` | Int32       | 4           | 5     |
| `0x09` | Int64       | 8           | 9     |
| `0x0A` | Float32     | 4           | 5     |
| `0x0B` | Float64     | 8           | 9     |

#### Primitive Tags: Logic

| Tag ID |                Name             |  TS8  |
| ------ | ------------------------------- | ----- |
| `0x0C` | Bool                            | 1     |
| `0x0D` | Bool (true)                     | 1     |
| `0x0E` | Bool (false)                    | 1     |

> Only use `0x0C` in schema definition

> Only use `0x0D` and `0x0E` in schema implementation

#### Container Tags: Set Contained Tag

| Tag ID |                Name             | PS8: # of bytes |
| ------ | ------------------------------- | --------------- |
| `0x0F` | Bitset                          | 1               |
| `0x10` | String (UTF-8)                  | 8               |
| `0x20` | BLOB                            | 8               |

> If the number of bytes value is 0 in the schema, then the container has a
> dynamic size in the implementation; otherwise, it has a fixed size

#### Container Tags: Single Contained Tag

| Tag ID |                Name             | PS8: # of elements | PS8: tag |
| ------ | ------------------------------- | ------------------ | -------- |
| `0x30` | Array                           | 8                  | 1        |

> If the number of elements value is 0 in the schema, then the container has a
> dynamic size in the implementation; otherwise, it has a fixed size

#### Container Tags: Contained Pair of Tags

| Tag ID |                Name             | PS8: # of elements |
| ------ | ------------------------------- | ------------------ |
| `0x40` | Associative Array               | 8                  |

#### Special / Metadata Tags

| Tag ID |                Name             |
| ------ | ------------------------------- |
| `0xFF` | Skip / Padding                  |
