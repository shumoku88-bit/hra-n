# 単一追記ログ：隔離されたバイト公開実験

Status: **synthetic byte-framing / POSIX process probe only. Production authority、会計 admission、世代 writer との同等性、power-loss 資格ではない。**

## 問いと範囲

一操作が複数の論理 stream に追記する場合、単一の framed append にまとめると中断・競合・再試行時にどのバイト列が見えるか。`test_transaction_log.py` は7段階の合成文字列（`journal.hra` / `policy.hra` / `scheduled.hra`）を生成し、SHA256付きJSON frameを検査する。最後の段階は journal と scheduled の同時追加。これらは**家計事実ではなく byte specimen**であり、旧三-stream CLI writerもLoam canonical writerも呼ばない。

2026-09-25 の canonical-only `hra-n init` / legacy CLI writer 退役後、旧版の「CLIが生成した7つの admitted generation の再構成」「Budget/Flow の一致」「別候補の予定完了をCLIで生成」という試験は実行不能となった。旧結果は Git history の固定参照 `e1e5f120d5cbafa63bb65a3b39af05ee0d94dcad` に残るが、現行CIや現在の canonical 意味との対応証拠として使わない。Loam比較元の歴史的参照は `3e3c96e72d46368b68d8f61aaa0785dd34728d8c`。Loam形式への変換や differential test は行っていない。

## 実行・主張できること

```sh
python3 -B experiments/test_transaction_log.py
python3 -B experiments/test_disk_transaction_log.py
```

- 完全frameは元の合成byte imageを再構成し、各frameの全byte-prefixは未完suffixを `pending` として区別する。
- checksum破損、重複、stale parent、未知streamを拒否する。checksumが正しくても不正なfact文字列はframingを通るため、**semantic admissionは別途必須**。
- `disk_transaction_log.py` は一時rootで `flock → authoritative re-read → exact synthetic-image whitelist → append → fsync → receipt` を試すPOSIX専用実験writer。process終了、半frameのexact-prefix修復、retry、short/zero write、fsync例外、同一parentから異なる二つのbyte候補の競争を検査する。
- whitelistは会計検証器ではない。競争する二つの候補も単なる合成bytesであり、Scheduled completionの参照整合性や複数authorityのatomic publicationを証明しない。
- process exitは電源断・kernel crash・disk write reorderではない。hashは認証でもrollback検出でもない。index、checkpoint、backup、長期容量、可読性、移行、TUIも対象外。

CIの該当stepが通っても、production writerのqualificationや旧世代との同値性は成立しない。再び会計observableを比較するには、Loam canonical dataを読み書きするAda側の共通admissionと、同じfault scheduleでのwriter比較を先に設計する。実データや旧三-stream運用経路を復活させない。
