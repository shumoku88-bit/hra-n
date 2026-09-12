# Household Observation v1

`HOBS1` is a read-only comparison surface for household projections. It is not
canonical household data, a persistence format, or a new semantic authority.
Its first concrete use is differential observation between LOAM and HRA-N.

The v1 slice exposes three already-demonstrated query families:

- Balance;
- explicit half-open Budget / Envelope window `[START, END)`;
- all-retained Capacity entitlement.

Adapters must call their existing Application / shared review boundaries. They
must not reimplement accounting arithmetic in the serializer.

## Framing

The stream is UTF-8, one record per line, with tab-separated fields. Identity
fields are existing single-line tokens. Numeric fields are exact base-10
integers with no grouping separators and no adapter-side decimal rescaling.
Record ordering is presentation only and has no semantic meaning.

Every record begins with `HOBS1`. A successful document ends with exactly:

```text
HOBS1<TAB>meta<TAB>status<TAB>complete
```

Consumers must reject a stream without that terminal record. An adapter should
load every required query before writing stdout so a query refusal does not look
like a partial valid document.

## Records

Metadata:

```text
HOBS1  meta  NAME  VALUE
```

Required v1 metadata is `schema=1`, `implementation`, `snapshot_kind`,
`window_start`, `window_end_exclusive`, `balance_scope`, `capacity_scope`, and
the terminal `status=complete`. A snapshot identity is emitted when the
implementation has one coherent retained snapshot identity.

Balance:

```text
HOBS1  balance  LOCUS  MEASURE  AMOUNT  ORIGIN_STATUS  POSTING_COUNT_OR_DASH
```

`ORIGIN_STATUS` is one of `known-zero-origin`, `unknown-origin`, or `conflict`.
A producer that cannot expose posting count writes `-`; it must not invent zero.
Scopes may differ between implementations, so absence of a row is not a parity
failure unless the declared scopes make the same row set observable.

Budget / envelope row:

```text
HOBS1  budget  PURPOSE  MEASURE  ENTITLEMENT  CONSUMPTION  REMAINING
```

`Remaining` is a derived observation. It is not retained merely because it is
present in HOBS1.

Capacity row:

```text
HOBS1  capacity  COORDINATE_KIND  COORDINATE_TOKEN  MEASURE  AMOUNT
```

`COORDINATE_KIND` is `purpose` or `unallocated`. A producer whose shared query
only exposes purpose coordinates declares that through `capacity_scope` rather
than fabricating an unallocated row.

Additional typed scalar observations:

```text
HOBS1  scalar  NAMESPACE  NAME  UNIT  VALUE
```

Scalars preserve useful implementation-specific diagnostics without widening
the comparison core. Current examples include Budget totals, unallocated funds,
conservation delta, evidence completeness, and counts.

## Comparison rule

Compare semantic keys, not line positions. For the v1 core:

- Balance key: `(locus, measure)`;
- Budget key: `(purpose, measure, window_start, window_end_exclusive)`;
- Capacity key: `(coordinate_kind, coordinate_token, measure)`.

A mismatch is evidence to classify, not proof that one implementation is wrong.
First distinguish input/snapshot differences, scope differences, semantic
definition differences, incomplete/conflicting evidence, and only then a likely
implementation defect.
