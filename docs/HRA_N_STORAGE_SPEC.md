# HRA-N Storage Specification
## 統一3ファイル構成による個人会計・家計ストレージ仕様

Status: **CANONICAL STORAGE SPECIFICATION v1.0**  
Formal Verification: Machine-proved in [`spec/alloy/hra_n_storage_schema.als`](../spec/alloy/hra_n_storage_schema.als)

---

## 1. 設計原則 (Design Principles)

HRA-N のストレージ設計は、Loam の 18 ファミリに及ぶ過剰断片化（学術的実験の遺物）を排し、以下の原則に基づいて極小・高密度に統合されています。

1. **自己完結型レコード (Self-Contained Records)**:
   1 回の取引の「日付」「金額」「勘定」「目的」「メモ」「訂正先祖」を同一行に保持する。複数ファイルにまたがる結合（Join）やハッシュ同期（CURRENT）を排除する。
2. **追記型不変性 (Append-Only Immutability)**:
   履歴は決して破壊（UPDATE/DELETE）されない。訂正や精算は `replaces:<id>` や `discharges:<id>` のリンクを持つ新しいレコードとして追記される。
3. **人間可読性とGit親和性 (Human-Readable Plaintext)**:
   `git diff` やテキストエディタで一目で意図が分かり、手動編集や修正パッチが容易。
4. **極小パーサー (Minimal Parsing Overhead)**:
   1 つのファイルを 1 回走査するだけで、SPARK 検証済みのインメモリ構造体が 100 行足らずのコードで直接構築可能。

---

## 2. ディレクトリ構成

```text
hra-data/
├── journal.hra    # 実取引・訂正・精算ジャーナル
├── scheduled.hra  # 予定・完了・破棄・置換ジャーナル
└── policy.hra     # 勘定役割・ゼロ起点・予算枠ポリシー
```

---

## 3. ファイル仕様

### (1) `journal.hra` — 実取引ジャーナル

実取引（Actual Events）、誤記訂正（Corrections）、貸借関係（Relations）、精算（Discharges）を記録する追記型ジャーナル。

#### 文法 (BNF)
```text
JournalFile  ::= ( Comment | Transaction )*
Transaction  ::= "TX" Space Id Space Date Space Flows ( Space Purpose )? ( Space Note )? ( Space Meta )* EOL
Flows        ::= Flow ( Space Flow )*
Flow         ::= Locus ":" Amount ( ":" Measure )?
Purpose      ::= "@" PurposeToken
Note         ::= '"' String '"'
Meta         ::= "replaces:" Id
               | "relation:" Debtor "->" Creditor ":" Amount
               | "discharges:" Id ":" Amount
```

* **デフォルト通貨**: `Measure` が省略された場合は `jpy` とみなす。
* **二重記帳の保存則**: 1 つの `TX` に含まれる `Flows` の総和は、通貨ごとに厳密に 0 でなければならない（$\sum \Delta = 0$）。

#### 実例
```text
# 1. 通常の支出
TX e0001 2026-04-04 paypay:-500 tobacco:500 @タバコ "タバコ"
TX e0002 2026-04-04 smbc:-1000 paypay:1000 @unmanaged "チャージ"

# 2. 開設残高
TX e0003 2026-04-04 paypay:192 equity:opening-balances:-192 @unmanaged "Opening Balance"

# 3. 過去の取引の訂正 (e0001 を e0004 に訂正)
TX e0004 2026-04-05 paypay:-520 tobacco:520 @タバコ "金額誤記訂正" replaces:e0001

# 4. 友人への立替（貸出関係の発生）
TX e0005 2026-04-10 smbc:-10000 debt-friend-k:10000 @貸借 "飲み会立替" relation:friend-k->household:10000

# 5. 立替金の返済回収（精算の発生）
TX e0006 2026-04-15 paypay:10000 debt-friend-k:-10000 @貸借 "立替返済受領" discharges:e0005:10000
```

---

### (2) `scheduled.hra` — 予定ジャーナル

将来の資金移動予定（Scheduled Obligations）とそのライフサイクル終端状態を記録する追記型ジャーナル。

#### 文法 (BNF)
```text
ScheduledFile ::= ( Comment | ScheduledRow )*
ScheduledRow  ::= "SCHED" Space Id Space DueDate Space Flows Space "status:" Status EOL
Status        ::= "open"
                | "completed:" TxId
                | "retired"
                | "replaced-by:" SchedId
```

#### 実例
```text
# 1. 完了した予定（e0120 の実取引として執行された）
SCHED scheduled-1 2026-09-08 smbc:-4810 wifi:4810 status:completed:e0120

# 2. 条件変更により置換された予定（scheduled-5 に差し替え）
SCHED scheduled-2 2026-09-15 smbc:-3000 gpt-plus:3000 status:replaced-by:scheduled-5

# 3. キャンセルされた予定
SCHED scheduled-3 2026-09-18 paypay:-1000 health-insurance:1000 status:retired

# 4. 現在オープンな予定（未到来または未執行）
SCHED scheduled-4 2026-10-15 smbc:-64000 rent:64000 status:open
SCHED scheduled-5 2026-09-15 smbc:-3300 gpt-plus:3300 status:open
```

---

### (3) `policy.hra` — 家計方針と静的境界

勘定科目の会計的役割、残高計算が数学的に保証されたゼロ起点、予算（Capacity）枠の宣言。

#### 文法 (BNF)
```text
PolicyFile ::= ( Comment | RoleDecl | ZeroOriginDecl | CapacityDecl )*
RoleDecl        ::= "ROLE" Space LociList ":" Space RoleType EOL
ZeroOriginDecl  ::= "ZERO-ORIGIN" Space CoordList EOL
CapacityDecl    ::= "CAPACITY" Space PurposeToken ":" Space Amount ( Space Measure )? EOL
RoleType        ::= "ASSET" | "LIABILITY" | "INCOME" | "EXPENSE" | "EQUITY"
```

#### 実例
```text
# ============================================================
# 1. 勘定科目の会計的役割 (Accounting Roles)
# ============================================================
ROLE smbc, paypay, cash, yucho, all-country: ASSET
ROLE debt-friend-k, debt-mother: LIABILITY
ROLE food, tobacco, rent, wifi, health-insurance, utilities, misc: EXPENSE
ROLE pension, support, allowance, lesson-income: INCOME
ROLE equity:opening-balances: EQUITY

# ============================================================
# 2. ゼロ起点エビデンス (Zero-Origin Coverage)
#    明示的にゼロ起点から完全記帳されている口座のみ残高計算を許可
# ============================================================
ZERO-ORIGIN smbc:jpy, paypay:jpy, cash:jpy, yucho:jpy, all-country:jpy

# ============================================================
# 3. 目的別予算枠 (Capacity Envelopes)
# ============================================================
CAPACITY 食費: 39000 jpy
CAPACITY 食費:ストック: 7000 jpy
CAPACITY 一般生活: 26000 jpy
CAPACITY タバコ: 29500 jpy
CAPACITY 固定費予定: 12700 jpy
CAPACITY 通院: 2000 jpy
```

---

## 4. 形式検証による安全性保証 (Formal Proofs)

本仕様は [`spec/alloy/hra_n_storage_schema.als`](../spec/alloy/hra_n_storage_schema.als) において SAT ソルバにより以下の性質が反例なしで証明されています：

1. **Self-Contained Extraction**: 単一レコードの走査で取引の全属性が確定し、結合クエリによる不整合が原理的に発生しない。
2. **Double-Entry Preservation**: 取引単位のゼロ和保存則から、全履歴の残高保存則が数学的に演繹される。
3. **Relation Discharge Safety**: 精算の合計が債権額を超過することは絶対にない。
4. **Scheduled Partitioning**: オープンな予定と終端（完了・破棄・置換）された予定は完全排他である。
5. **Epistemic Honesty**: ゼロ起点宣言のない口座の残高を「既知」と誤認することは決してない。
