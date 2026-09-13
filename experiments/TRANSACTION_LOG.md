# 単一追記ログ：物理的な公開単位の比較

Status: **隔離された表現・POSIX writer実験。production採用・移行・power-loss資格ではない。**

## 問いと固定参照

- HRA-N: `e1e5f120d5cbafa63bb65a3b39af05ee0d94dcad`。比較元は `Storage.Generation_Transaction.Commit`、既存CLIによる合成履歴。
- Loam: `3e3c96e72d46368b68d8f61aaa0785dd34728d8c`。local source reviewのみ。Loam形式への変換・差分実行はしていない。
- 圧力: generationごとの全streamコピーと、複数streamにまたがる操作の公開手順。
- 仮説: **意味上の三streamを維持したまま、一操作の追加分を一つの物理frameに束ねれば、全コピーを避けられる可能性がある。**
- 対立仮説: 単一ファイルなら事実を一行ずつ追記するだけで、一操作の原子性と復旧が不要になる。

今回の利用者指示に基づく探索であり、P0不具合修正の完了や優先順位全体の変更ではない。

## 現行方式について訂正しておくこと

HRA-Nの現行writerは、三つの運用authorityを独立にcommitする分散2相commitではない。
一つのwriter lockの下で選択世代を再読込し、candidate世代の三streamを準備・admitしてから、
**一つのCURRENTをactivation edgeとして切り替える**。選択済み世代は変更しない。
失われた応答に対しては次世代のexact candidate一致を確認する経路がある。

したがって「三ファイルだからロック・復旧コード数千行が必要」「一ファイルなら全部消える」は
この実装からは導けない。比較すべきは、現行の単一activationと、候補のframe公開・復旧の全体である。

## 実験の最小構成

`test_transaction_log.py` はPython標準ライブラリの**offline probe**。
`disk_transaction_log.py` と `test_disk_transaction_log.py` はPOSIX上の実験専用writerとprocess試験。
HRA-N productionへPython依存・新reader・writer・第二のauthorityを導入しない。
既存Ada CLIで新しい一時householdを作り、次の7世代を生成する。

1. init
2. Foodへ100 JPYのcapacity
3. food→Foodのroute
4. 月末の10 JPY記帳（日本語説明）
5. 12 JPYへの訂正
6. 20 JPYのScheduled作成
7. Scheduled完了（Actual追加とterminal追加を同じ操作で公開）

各世代の三streamが前世代のbyte-prefixを保持することを確認し、追加分だけをframeへ入れる。
初期世代もempty byte imageからの追加として扱う。空imageを有効なhouseholdとは認定しない。

候補frameは次の一行。内部改行はJSON escapeされる。

```text
SHA256(payload) SPACE JSON({parent: previous_hash, delta: {three stream suffixes}}) LF
```

これは比較用encodingであり、正データ形式の提案確定ではない。
stream名・Event ID・correction・description・measure等は変更しない。
hash chainは実験の順序・破損検査用で、会計の新しい事実や承認済みsnapshot契約ではない。

## 法則・結果

実行（HRA-N root）:

```sh
rtk err ./tools/build
rtk test python3 -B experiments/test_disk_transaction_log.py
# 既存Ada test runnerをbuildした後、現行writerの比較基準も確認する:
rtk test ./tests/bin/test_runner Test_Generation_Transaction
```

2026-09-13 UTC、local macOS/POSIX実行: **9 tests PASS**（offline 4件を含む）。
現行 `Test_Generation_Transaction`: **37 assertions PASS**。
CIにも独立stepを登録するが、Linux/remote実行成功は未確認。

| 検査 | 得られた証拠 |
|---|---|
| 各世代の再構成 | 三streamのUTF-8再encode後の内容が元のbytesと一致。訂正履歴・日本語説明を保持 |
| 利用者への答え | 再構成したread-only unversioned rootと元の選択世代でBudget/Flow出力一致。Snapshot labelだけ明示的に対応付け、数字・statusは正規化しない |
| 独立期待値 | consumption = 訂正後12 + 完了20 = 32、capacity100、remaining68、Flow expense32/net -32 |
| 各frameの全byte-prefix | 2,138 cutを検査。完全frameのLFが届くまでは直前の三stream image、完全時は新image。途中のsuffixは`pending`として明示し、黙って正常扱い・切捨てしない |
| 素朴な事実単位の単一ログ | Actual行の直後で切ると、末尾は完全な行なのにScheduled terminalがない。**「壊れるのは最後の行だけ」では一操作の原子性を説明できない** |
| 破損・重複・順序 | checksum破損、欠けた前提frame、同一frame二重追加、途中frameへのそのまま再追記、未知streamを拒否 |
| admissionの独立性 | checksumの正しい不正canonical factはcontainerを通る。byte integrityは会計admissionを代替しないことも試験 |

保存量はこの7世代の三stream実bytes合計 **3,385 bytes** に対し、frame列 **2,138 bytes**。
ディレクトリ・selector・block割当・index・checkpoint・backupを含まない小標本。
長期性能、総実装量、同機能での削減率の証拠にはしない。

## 実書き込み・途中終了・再試行

実験writerは一時root内で `flock → authoritative re-read → candidate admission → append → file/parent fsync → receipt` を行う。
**admissionは既存CLIが生成した合成imageのexact whitelist**。本番の完全admissionを再実装したものでも、
そのAPIの安全な再利用が完成したものでもない。任意の家計データを受け入れるwriterではない。

| 実験 | 結果・範囲 |
|---|---|
| 子processの強制終了 | lock後、admission後、frame半分のwrite後、全write後、fsync後に `os._exit(73)`。Pythonのfinallyを実行せず終了し、別processから再読込・retry |
| 公開前の終了 | 既存prefixがそのまま残る。半frameはpendingと明示 |
| 全write後／fsync後の応答喪失 | このOS上では完全な新imageが見える。retryは再fsyncして同じreceiptを返し、frameを重複追加しない |
| 同じ操作のpartial tail | 所有権下でexpected headとcandidateのexact byte-prefixを確認し、末尾をtruncate・sync後に再送。tail修復直後の強制終了からのretryも確認 |
| 別操作のtail／完全frame破損 | 自動修復せず拒否。元の実験log bytesを変更しない |
| 同時writer | 同じ親から異なる二つのScheduled完了候補を用意し、pipeで開始を解放する2process競争を5回。各回一方だけ成功、他方はstale、追加は1frame |
| admission／I/O失敗 | whitelist拒否では追記なし。fsync例外ではreceiptなし。ゼロ進捗writeは失敗、3byteずつのshort writeでも完全frameを構築 |

競合候補も既存CLIで別の合成householdへ完了を公開して得る。予定完了の会計・参照整合性をPythonで推測しない。

### 現行writerとの比較範囲

現行Ada試験は、activation前各段階の故障、activation後の応答喪失、exact candidateのretry、
stale、admission拒否、2task競争を検査する。今回も37 assertionsが通った。
共通して必要だったのは**単一所有権・再読込・admission・公開境界・durable receiptとretry**であり、
単一logにしたことでこれらが消えるわけではなかった。

ただし、同じfault scheduleを同じharnessで両writerへ注入する比較はまだ完成していない。
現行Ada側は協調的fault returnとtask競争、候補側はprocess終了とprocess競争である。
この非対称性を、同等のクラッシュ資格・性能比較として扱わない。

## 残る責務と失敗境界

prefix切断もprocess終了も、電源断・kernel crash・disk write reorderの実験ではない。

- `pending`を持つimageは、完全authorityとして自動提供しない。今回修復できるのは同じexpected parentとcandidateが手元にあるexact prefixだけ。別候補・失われたrequestの復旧規約は未実装。
- writer lock、所有権取得後の再読込、stale rejectionは残る。hash chainで順序不整合を検出できても、同時writerを安全に直列化したことにはならない。
- complete LFとchecksumが読めても、fsync・ディレクトリ同期・durable receiptを証明したことにはならない。
- retryは直後の同じcandidateに限定。さらに別のcommitが進んだ後の過去request照会や、永続的なrequest/receipt台帳は未実装。
- canonical syntax・参照閉包・per-measure保存・Scheduled lifecycleのadmissionは既存境界の責務。
- checksumは認証ではない。末尾の完全frameを丸ごと失うrollbackは、それだけでは検出できない。
- malformed/partial suffixと途中破損を無条件に同じ修復で処理してはいけない。
- 全log走査の時間・メモリ、checkpoint、compaction、backup/restore、schema変更、長期capacityは未資格。POSIX fsyncの成功をhardwareまで含む無条件の永続性保証としない。
- JSON escapeと長いhash行は人間の読みやすさを悪化させ得る。単一ファイル化をdiscoverability改善と同一視しない。
- probeのframe内容は追記可能な三stream suffixに限定。全データの移行可能性を証明しない。

TUIは削らない。今回は同じ既存Queryに再構成bytesを渡す比較であり、候補logをTUIへ接続したり、
候補のPTY・表示品質を検証したりしたわけではない。

## 採否・Loamへの還元packet

**候補維持、production採用保留。** 素朴な一行ずつの追記だけで操作原子性が得られるという仮説は、
Scheduled完了の最小例で反証された。transaction frameによる表現の可能性は残る。

Loamへ返せるのは特定のencodingではなく、
**「論理的な事実の分離と、物理的な公開単位は別。単一ログにも一操作の境界・復旧・admissionが必要」**
という再現可能な比較材料。Loamの不具合を発見したという主張ではない。

- 方向: HRA-N → Loamの検討材料
- 状態: local probe検証済み、Loamへ未提案・未採用
- 前提: append-only synthetic history、既存Ada admissionによる7世代、有限byte-prefix fault model
- trade-off: 全世代コピーを避ける可能性 vs framing/checkpoint/復旧/可読性の負担
- 次の判別実験: 現行generation publisherにも同じprocess終了・競争harnessを適用し、fault範囲を揃える。
  その前提となるadmission再利用境界を確認する。現行の完全candidate admissionを共有APIとして扱えず
  whitelistから独立した本番相当候補へ進めないなら、F08の境界整理を先に行う。
  追加のコピー削減より、意味を二重実装せず同じ故障条件で比較できることを優先する。

その比較なしに現在のwriterやimmutability guardを削除しない。実データ移行は別の承認と資格確認が必要。
