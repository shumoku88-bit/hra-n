# HRA-N 長期保険・小核設計・TUI品質監査

## 0. この文書の使い方

**目標：本命であるLoamが、小さな概念・保持事実・機能・部品から豊かな会計／家計機能を導く成果を、Ada＋SPARKで長期間利用できる保険として育てる。HRAの会計・検証・端末資産を活かし、HRA/LoamのTUI品質を最低ラインにさらに磨く。**

product objectiveと相互検証手順の現行authorityは[`LOAM_ALIGNMENT.md`](LOAM_ALIGNMENT.md)。Loamは現在も開発中であり、固定仕様でも成功確定済みの完成品でもない。**HRA-Nも正データの形と最小の保持根拠を模索し、反例・簡約・使い心地の発見をLoamへ返す。** 一方向の移植先に限定しない。避けるのは無根拠な意味の分岐や機能競争であり、根拠付きの独立した設計探索ではない。

これは実装指示を兼ねた監査であり、全面書き直しの提案でも、機能数の採点でもない。後続pitは対象箇所を再確認し、反例をテスト化してから小さく修正すること。未検証の疑いを確定不具合として扱わない。

- 初回監査対象：HRA-N `fb2725d`、比較：HRA `eace8b9`、Loam `6869de2`。初回開始時の3 working treeはclean。この再現証拠を、後から確認したLoamのSHAで更新・再認定しない。
- 方針改訂時のLoam進捗は`CAPABILITY_MATRIX.md` §4の単一checkpointで管理する。そこに記録したsource reviewは、移植完了・比較test成功・全面互換を意味しない。
- 根拠はこのrevisionのファイルと関数。以下の相対パスは特記しなければHRA-N内。`../hra/`、`../loam/`は比較元。
- **動的確認**＝現在ソースをbuild後、公開可能な合成fixtureで再現。
- **静的確認**＝当該実装の制御・データ経路を確認。実端末・障害条件すべての再現を意味しない。
- **設計不足**＝公開・長期利用目標に対し契約や証拠が足りない。直ちに現在データが壊れるとの主張ではない。
- P0＝誤判断・情報欠落を先に止める。P1＝日常利用／公開前に必要。P2＝継続的な使い心地・拡張。これは監査の優先度であり、既存CAPABILITY_MATRIXのフェーズ番号とは別。
- 現在の運用authorityはLoam。初回監査は実データを読まず合成fixtureで実施。後続の利用者報告の診断では、配置・権限・選択世代と、指定された1取引の説明の有無だけを確認した。家計本文はログ・文書へ転載していない。データの変更、並行記帳、自動同期はしていない。

この文書は監査基準点であって、新しいdomain authorityではない。修正後の仕様・能力状態は既存の設計文書とCAPABILITY_MATRIXを更新し、この文書を完了作業日誌にしない。

## 0A. 利用者が求める最低品質と追加報告【後続pit必読】

### 明示された要求

> TUIも細部までHRAやLoamをお手本にし、その品質を最低ラインとして、さらに磨きたい。

**HRA/Loamは着想だけの参考ではなく、日常操作の品質を比較する最低基準である。** 同名workspaceがある、キーが反応する、PTYが通るだけでは達成ではない。両者の優れた点を具体的な操作で比較し、HRA-Nで劣化させず、より分かりやすく整える。既存の不具合・意味の曖昧さまで再現する要求ではない。

対象は外観だけではない。情報密度、説明・金額・単位の優先順位、カレンダーからの到達性、日本語、検索、選択、編集、確認、取消、競合後の復帰、画面間の状態保持、端末サイズへの対応、正データへのアクセスまで含む。CLI/kernel完成後に余力で行う装飾作業として後回しにしない。F01〜F08の誤答封じと両立させ、縦のsliceごとに品質を上げる。

### 利用者報告1：フォルダを見ても正データの中身が見えない

**報告：** 正データが変になったように感じ、TUIでもフォルダでも以前より見にくい。

**確認済み：** 診断時の`hra-data`直下には三streamがなく、実体は隠しディレクトリ`.hra/generations/<selected>/`にあった。CURRENTが選択する世代のjournal/policy/scheduledは存在し、読み取り権限もあった。内容の完全性・移行前後の同値性はこの確認だけでは保証できない。ファイルの存在だけで「データ消失なし」「移行正常」と断定しない。

**問題の位置づけ：** crash-safe publicationは必要だが、「自分のデータを普通の道具で開いて理解できる」品質が不足している。隠しフォルダ表示のショートカットを教えるだけでは設計上の解決にならない。

**後続pitの作業：**

- authoritative snapshotの場所と現在の選択を、人間に分かる形で案内する。
- 閲覧、監査、export、backup、編集の違いを明示する。表示用exportを第二の正データにしない。
- visible read-only view／明示的export／snapshotを開く操作等を比較し、最小の仕組みを選ぶ。具体方式は未決定。
- CURRENTを跨いで内容が混ざらず、出力にはsnapshotと生成条件が付くようにする。
- 選択世代を直接編集可能にするsymlinkやrootファイルの二重管理で、見かけだけ改善しない。

**完了条件：** 利用者がTUIまたは短いdocumented操作から、現在の正データの場所・snapshot・三streamを確認し、通常のviewer/editorで安全に読める。別machineでbackupから読める。古いexportを現行authorityと誤認しない。

### 利用者報告2：カレンダーの記帳内容が「- 内部ID」に見える

**報告：** カレンダーから見ると、最近の記帳内容が`- <event-id>`のように表示され、何を記帳したか読み取りにくい。

**確認済み：**

- `src/ui/hra_n-ui-home_tui.adb`約339〜386行は選択日のActualを`Order_Oldest_First`で取得し、最大3件を表示する。
- 行は`"   - " & Id_Str & "  " & Desc_Str`。内部IDが先、説明が後で、金額・measure・支払元/先のsummaryはない。
- 指定された1取引では、保存されたTXに空でないquoted descriptionが存在した。内容はここへ転載しない。

**未確認：** 実際の利用者端末で説明がclipされたのか、情報順位のためIDしか認識できなかったのか、別の表示条件があったのかは未確定。全取引の説明保持や移行のlosslessnessも未検証。「説明が残る1件」を根拠に全データ正常とは言わない。

**要求する表示品質：**

- 一覧の主役は記帳の説明とexact amount/measure。内部IDは詳細や補助表示へ下げる。
- 単純movementは移動元→先を読み取れる。split/multi-measureは一つの金額へ潰さず、複数効果の明示と詳細への入口を持つ。
- 説明なしの場合は「説明なし」を明示し、IDだけを内容の代用品にしない。
- 長い説明の省略は見た目だけに限定し、選択→詳細で全文・全effects・provenanceへ到達できる。
- Homeは選択日の一覧なのか最近の記録一覧なのかを明示する。最近の記録をうたうならoldest-first先頭3件で代替しない。選択日と記録時系列も混同しない。
- 日の件数、calendar marker、current/history scope、並び順、隠れている件数、詳細actionを一致させる。
- 80×24等の通常幅で説明・金額が読め、compact幅でも内部IDだけになる設計にしない。

**完了条件：** 同じ合成取引をHRA/Loam/HRA-Nで比較し、カレンダー→選択日→取引詳細→訂正→元の日へ戻るまで確認。日本語、長文、説明なし、4件以上、split、複数measure、日付訂正、reversalを含める。比較元が非対応の意味は無理に変換せず、対応範囲を明記する。正データの説明やIDを書き換えて表示問題を隠さない。

### 引継ぎに必ず含める成果物

1. HRA/Loamのどの画面・操作・実装・試験を比較したか。
2. HRA-Nの現状との差と、採用／不採用の理由。package単位の丸ごと移植は不要。
3. 合成データによる改善前後の画面例と操作経路。家計の実画面をpublic fixtureにしない。
4. typed queryの同値性、PTY、pure interaction/layout test、手動の読みやすさ確認の各結果。
5. 意味・writer safety・アクセシビリティを維持したことと、まだ検証していない範囲。

**現在までに行ったのは監査・診断・文書化のみ。この報告に関するTUI実装修正、データ修復、移行、配置変更はまだ行っていない。**

## 0B. 正データ探索とLoamへの還元【利用者による目的の補足】

**利用者の要求：HRA-Nでも正データの形を模索する。その追従・比較がLoam側にとっても良い発見になる可能性を高めたい。**

これは後回しの副産物ではなく開発の進め方に含める。保険を作るために異なる基盤で考え直すこと自体を、共通の思い込みを発見する機会とする。

- 現行の`journal.hra / policy.hra / scheduled.hra`やgeneration layoutは実装中の契約であり、永続の設計制約ではない。Loamの保存形に合わせる必要もない。
- ファイル配置だけでなく、独立に保持する事実・IDと参照・時間・admission・publicationの単位を検討してよい。観測可能な違いを消さず、導出可能な重複だけを減らす。
- 現在の形と最小代替案を、同じ合成履歴・期待値・failure条件で比較する。人間の読みやすさ、TUIへの接続、proof、保存量、復旧・移行負担も評価する。
- 反例が既存の意味の契約の不足を示すなら、Loamへ無理に一致させず、契約そのものの修正候補として示す。片方を常に正解扱いしない。
- 発見は、両repoの固定SHA・最小合成例・法則／仮説・結果と未検証範囲・trade-off・Loamへの適用条件付きで返す。提案／検証／採用を区別する。
- sliceごとに還元候補を確認し、定期レビューで未解決のreturn queueを見る。「発見なし」も正当な結果。新しい研究や文書を毎回作るquotaにはしない。

**完了条件：** HRA-N側の比較から得た具体的な知見を、Loam担当pitが実データやこの会話なしで再現・反証・採否判断できる。Loam側で採用された場合は採用revisionを次回比較へ取り込み、必要なら双方の仕様・試験を更新する。採用されない場合も理由と適用範囲を残す。

具体手順・引継ぎpacketは`LOAM_ALIGNMENT.md` §3、現在の未解決候補は`CAPABILITY_MATRIX.md` §5。現段階では探索の方針と候補を記録しただけで、新形式の資格確認やLoam側への提案・変更を行ったわけではない。現行の正データを直接書き換える許可でもない。

## 1. 総評：小さな核から豊かな機能を作る「保険」になっているか

**方向性は一部合っているが、システム全体ではまだ達成していない。良い核はある一方、Loamの成果を独立して維持できる長期保険としては未完成である。**

今回の位置づけの明確化により、評価の中心を「独立製品として機能が揃ったか」から次へ改める：

| 評価軸 | 現状評価 | 次に必要な証拠 |
|---|---|---|
| 少ない意味から豊かな数字を導く | measure、correction、coverage等の方向性はよい。ただし機能別の計算経路が残る | F01〜F08/F14：同じ根拠とintervalから各surfaceが同値な答えを導く |
| システム全体の小ささ | Coreの小ささだけでは不十分。read/計算/UIの重複があり、行数削減成功ではない | 独立保持事実・重複state/経路・同じ能力範囲での規模比較 |
| Loamとの相互検証 | 比較元と着想はあるが、言語中立の契約＋固定SHAごとの比較資格と逆方向の還元経路が不足 | observable単位の仕様・合成期待値・意図的差異・正データ候補・双方の採用状態 |
| 異なる基盤での長期継続 | Ada/SPARKとgenerationは有力な材料だが、それだけでは保険にならない | F09〜F12/F24：長期容量、独立build、読める仕様/データ、移行・復元 |
| 日常利用の引継ぎ | workspace数は増えたが、記帳の認識・検索・編集・復帰が粗い | §0A/F17〜F23：HRA/Loamと同じ操作を最低限同じ品質で完遂 |

Lean 4の将来のtoolchain/API保守負担への不安に対して、別基盤を用意することは合理的な目的。ただしLean 4が不安定になると断定せず、Adaの長期安定も無条件には仮定しない。**将来Loamを実行できなくても意味とデータを読めて、HRA-Nで正しく継続できること**を保険の判定にする。

次は画面や独自概念を無目的に増やすより、同じ意味の契約、誤答封じ、共通投影、データ継続性、日常TUIを縦に完成させる段階である。その過程で正データの代替形や契約自体の不足も探索する。保険という位置づけは、設計を凍結したりUIを低品質の予備画面で済ませたりする理由ではない。

特に重要な判断：

1. **7タブは7つのqualified reportを意味しない。** 月末・measure・分類変更・unknown・exit statusの境界に具体的な不整合がある。
2. **SPARKでbounded kernelを守ることと、全履歴を小さな固定配列に制限することは別。** 1,024件の生涯上限では日常家計の10年に届かない。
3. **generation publicationは保持すべき強み。ただしbackup、restore、format migration、保存量の設計までできて初めて長期保存になる。**
4. **UIの完成度は色やタブ数より、選択→根拠→編集→確認→保存→復帰の一貫性で決まる。** 現在のdrill-down、再読込、検索、入力、mouse所有権には接続の粗さがある。
5. **Loamの現在の成果を定期的に確認し、意味の契約を選んで継承する。** code/packageの盲目的翻訳も、旧版Loamの凍結コピーも避ける。HRAのReport観測と金融法則は再利用するが、旧8ファイル構成やontologyを保険の正解にしない。
6. **同じ結果だけでなく、少ない独立事実から再構成できることが目標。** Report/Remaining/Headroom等をcanonical stateへ増やす前に、既存の根拠で答えられるかを確認する。

### 残すべき資産

- measureごとの保存則、unknownとknown-zeroの分離、明示的correction/reversal/terminal evidence。
- immutable generation、単一CURRENT、writer lock、stale rejection、candidate admission、fsyncとreceiptの経路。
- shared Intent/Proposal、CLIとTUIの実行経路、既存CLI・PTY試験。
- formal resultをbounded evidenceとして扱う慎重なclaims policy。
- Core / Application / Storage / UIという方向性。問題はこの境界の徹底不足であり、層を全部捨てる理由ではない。

### 初回監査の実行証拠（方針改訂で再実行したものではない）

| 実行 | 結果・範囲 |
|---|---|
| `rtk err ./tools/build` | 成功。以下のCLI再現はこのbuild後 |
| `rtk test python3 tests/test_cli.py` | 成功、unittest 5 tests。大きなlifecycle test内に多数の操作がある |
| `rtk test python3 tests/test_tui_pty.py` | 成功。既存Home〜Reports操作とunknown/conflict Statement描画 |
| `./tools/metrics --loam-root ../loam` | HRA-N production Ada 26,401 code、UI全体12,078、Curses slice 7,666。Loam production Lean 22,372、TUI 7,524 |
| 本文の合成CLI反例 | 月末漏れ、measure混入、分類変更MoM、unknown net worth、Attention打切り、Audit exit、scheduled未検査を再現 |

初回監査ではSPARK、Alloy、TLC、SPIN、full Ada suiteは再実行していない。GitHub latest CIも取得していない。今回の方針改訂はMarkdownのみで、build/test/proofは再実行せず、文書の差分・リンク・構造を確認した。既存テスト成功は監査反例を否定しない。人間による全画面の見た目レビュー、電源断、ネットワークFS、全OSでの検証も未実施。

サイズは言語・測定範囲が違うため優劣の採点ではない。ただし「Loam同等以上で実装を大幅削減した」という主張は現在の数値でも成立しない。単なる行数削減を修正の目標にしない。

## 2. P0：最初に止める誤答と情報欠落

### F01 — Budget/Pace/Auditで月末日が集計から落ちる【動的確認】

**根拠：** `src/application/hra_n-application-budget_window.adb:In_Half_Open` は `[Start, End)`。一方 `src/ui/hra_n-ui-report_tui.adb:Generate_Report_Lines` のBudget/Pace/Auditは `End_D => Days_In_Month(...)` を渡す（約399/584/922行）。画面は1日〜末日を表示する。

**反例：** 9/1 Foodへ100 JPY容量、9/30 Food支出10。Budgetは `Entitlement=100, Consumption=0, Remaining=100`、Daily Flowは月支出10。

**影響：** 毎月最終日の支出と容量変更が外れ、Remaining、pace、backingの判断まで連鎖する。

**修正：** 日付区間型を共有し、月指定を `[月初, 翌月初)` に一度だけ正規化する。Statementのmonth-end as-ofとflow intervalは別の型／入力として保持する。

**完了条件：** 28/29/30/31日、12月→翌年、月末訂正・月末reversal、容量effective日について、Budget/Pace/Audit/Flowの期待値を固定。最大サポート年で翌月境界が表せない場合も明示的に拒否する。単純な全呼出先の「+1日」貼付で終えない。

### F02 — capacityのmeasureがBudgetで失われ、USDがJPYになる【動的確認】

**根拠：** `Storage.Policy_Reader` のTRANSFERはcurrencyを保持。`Application.Budget_Window.Project_Budget_Window` は `Mov.Currency` を照合せずPurpose単位で加算。`UI.Report_TUI` のJPY guardはJournal effectsだけを調べ、表示はJPY固定。

**反例：** journal空、policyに `TRANSFER unallocated Food 100 usd 2026-09-01`。`report --budget -m 9 -y 2026` は成功し、Food 100と `Unallocated Funds : -100 JPY` を表示。

**影響：** 物理側をJPYに制限してもcapacity側からcross-measure混入できる。「unsupportedを拒否」の法則が破られる。

**修正：** 当面はscalar Budget/Pace/Audit/Budget_Queryの入力measureを全平面でfail closed。長期はcapacityのcoordinateにmeasureを含めるか、単一measure authorityを明示してadmissionで守る。通貨換算を暗黙に導入しない。

**完了条件：** JPY journal＋USD capacity、空journal＋USD capacity、同一PurposeのJPY/USD混在、foreign scheduled pressureを含む合成例が各surfaceで同じ拒否／typed per-measure回答になる。

### F03 — 月次Flowを月末分類済み残高の差から作るためMoMが誤る【動的確認】

**根拠：** `src/application/hra_n-application-mom_query.adb:Project` は3月末の `Statement.Project` を差分化。Statementは各as-ofのRoleで累積全額を分類。Daily_Flow_Queryはoccurrence-day Roleを使用する。

**反例：** 8月にfoodへ支出10、foodを9/1にEXPENSEからASSETへ変更、9月取引なし。MoMは9月 `Total Expense=-10`、expense明細foodの9月値は0。Daily Flowの9月expenseは0。**surface間だけでなく同じMoMの明細と合計も不一致。**

**修正：** MoMのIncome/Expense/Net Savingsは共通interval-flow projectorから得る。Net Worthだけmonth-end stockから得る。Role変更をreclassificationとして見せるなら通常支出と別observableにする。

**完了条件：** Roleの途中変更・撤回相当・後日訂正、年度境界、refund、reversalの越月について `sum(details)=totals`、`MoM.flow=DailyFlow.totals`。安定Roleの例だけでは完了にしない。

### F04 — unknownなstockをMoMがNET WORTHとして表示する【動的確認】

**根拠：** `UI.Report_TUI` のMoM branchは `Query_Partial` の警告後にも `NET WORTH (Month-End Stock)` を無条件に数値表示。`Application.MoM_Query` もqualified stockとretained changeを同じ数値フィールドに入れる。

**反例：** `cash:-10 food:10`、RoleのみでZERO-ORIGINなし。MoMはPARTIALを表示しながら `NET WORTH ... -10 0 -10` を出す。

**修正：** metricごとのavailabilityを設ける。未知stockはUnavailableと理由、表示可能なretained-change subtotalはその名で表示。全体PARTIALの小さな警告を「数値の意味を強めない」保証の代用にしない。

**完了条件：** unknown origin、assertion conflict、片月だけ不完全、unclassifiedの4例で、CLI/TUIのstockが金額ゼロや純資産として表示されない。既存 `test_cli.py` のMoM試験はPARTIALの存在だけなので負のassertionも追加する。

### F05 — Audit内部のquery拒否が成功exitになる【動的確認／他branchは静的確認】

**根拠：** `UI.Report_TUI.Generate_Report_Lines` は `Result_Status := Query_Complete` で開始。AuditはStatement/Balance拒否時にERRORをemitしてreturnするがstatusを更新しない。Statement/Balance branchにもstatus伝播漏れがある。Export_Cliは `Query_Rejected` の場合だけ非ゼロ終了。

**反例：** Role 128 loci＋それ以外のcash/foodを使うTXでStatement account bound超過。`report --audit` は `[ERROR] Audit projection rejected` を出してexit 0。

**修正：** rendererがstatusを再構築しない。typed Report QueryのstatusをそのままCLI/TUIへ渡す。PARTIALをexit 0とするか専用codeとするかは契約で定めるが、Rejectedは必ず非ゼロ。

**完了条件：** 全7タブ×complete/partial/rejected/overflowをtable-driven試験化。stdout/stderr、終了code、見出しとbadgeの一致まで確認。`[PASS]`が一つあれば全体成功という判定は禁止。

### F06 — Attention/Relationなどが上限で黙って欠落する【Attention動的確認、隣接経路静的確認】

**根拠：** `Application.Attention_Query.Execute` は `exit when View.Count >= Max_Query_Rows` 後、Success/Query_Completeを返す。domain Attention上限256に対しquery上限64。`Relation_Query.Execute` にも64件打切り。`Budget_Window.Find_Or_Add_Purpose` は32枠超過時にFalse、呼出側は `null`。

**反例：** open Attention 65件がCLIで `64 open`、65件目なし、exit 0。これは表示ページサイズではなく「全件結果」としての静かな欠落。

**修正：** 明示的pagination＋total/has-more、またはbounded projection rejection。open countは全件由来。Purpose超過で集計を欠落させない。Relation detailのlinked-row上限も個別に確認する。

**完了条件：** 各上限−1/上限/上限＋1、閉じた項目が前半を占めるケース、超過項目だけに重要なdue/claimがあるケース。最終件まで到達できるか明確な拒否になる。

### F07 — 「全資産＝使える資金」「残予算÷残日数＝SAFE」の意味飛躍【静的確認・既知課題を具体化】

**根拠：** `UI.Report_TUI` 約468/1018行の `Funding_Assets := Summary.Total_Assets`、Budget/Auditに `SOLVENT - 100% Backed`。PaceはTotal_Remainingを日数で割り `SAFE DAILY TARGET` と表示。`Budget_Query` もjournal/policyのみ読み、Scheduled圧力を合成しない。

**影響：** 非流動資産・引落予定・用途制約を無視して「安全に使える」と受け取らせる。known originはliquidityの証拠ではない。予算権限、物理残高、将来支出は別平面。

**修正：** funding対象coordinate、観測日、未決済／Scheduled圧力、coverageを明示したApplication queryができるまで、SAFE/SOLVENTを撤去または単なる「残予算の日割り参考値」へ降格。固定500 JPYのTIGHT判定もhousehold lawではなく表示設定／説明付きheuristicとする。

**HRA資産：** `../hra/src/hra-household_report_observation.ads` のBacking_Report_Line、`hra-cycle_spending_pace.ads` のEligible_Assets/Automatic_Deductions/Unavailable。意味を比較し、旧account構造を移植しない。

**Loam資産：** `CycleBudgetReview`、`docs/TUI.md` のknown-through、explicit current window、Scheduled pressureの境界。

**完了条件：** 非流動資産だけ、資金ありでも予定引落で不足、未設定funding、unknown Scheduled coverage、返金・予定取消を含むqualified answer。画面が運用上の推奨を行うならその根拠へ辿れること。

### F08 — full admissionが共通Query入口で保証されていない【動的＋静的確認】

**根拠：** complete candidate admissionは `Storage.Generation_Transaction.Commit` 内のローカル `Admission_Failure`。Statement/MoM/Reportはjournal/policyを個別read、Actualはjournalのみ。Path_Resolverはversioned三ファイルの存在を検査するが意味のadmissionではない。

**反例：** 正常journal/policy＋`scheduled.hra=INVALID` のunversioned合成rootでdoctorはScheduled Life FAIL・exit 1、`report --audit` は複数のPASS・exit 0。

**注意：** これは当該読取経路の不一致であり、正常publisherが壊れたgenerationを公開すると立証したものではない。破損・import・legacy入力に対するfail-closed契約の穴である。

**修正：** parser結果とadmitted snapshotを型で区別し、readとcommitで共通のcomplete admissionを使用。pure Projectはadmitted値を消費する。部分stream inspectionはdoctor/import診断として明示し、qualified household answerと分ける。

**完了条件：** 三streamの各破損、跨stream dangling completion、破損selected generation、legacy入力を全public queryで検証。同一snapshot内でhealthとreportのadmission判断が食い違わない。

## 3. P1：長期使用を妨げる設計

### F09 — bounded proofと「生涯記録容量」が混同されている【静的確認】

**根拠：** `Core.Validity` 1,024 entries、Description/Metadata各1,024、Scheduled 128、Capacity movements 256、Assertions 256、Windows 64。Generation_TransactionはJournal.EventsがMax_Validity_Entriesを超えると拒否。Actual_Queryは選択日で絞る前に全journal件数を検査する。

**現実との距離：** 1日3件なら1,024件は約341日。月5予定ならScheduled 128件は約26か月。月1WINDOWをappendする運用なら64件は約5年。これらは利用量の仮定であって実測ではないが、10年目標との不整合は明白。閉じた項目もimmutable履歴として残る。

**修正：** 取引内bounded arithmeticと全履歴storage/indexを分離する。全履歴のidentities/correction closureを守りつつ、streaming/index/paginationまたはqualified checkpointを設計する。単純な定数10倍化や履歴削除は根治でない。

**完了条件：** 10年・1日10件なら36,500通常取引＋訂正＋予定＋assertionを含む合成workloadでread/write/replayが成立。warm navigation、cold load、commit、memory、保存容量を同条件で記録する。上限は利用者文書とdiagnosticに公開する。

### F10 — generationの全コピーと全再読込が長期量で重い【静的確認、性能未計測】

**根拠：** `Application.Proposal` は三stream全体をUnbounded_Stringとして保持。`Generation_Transaction` は毎commit三ファイルを書き、全体を再parse。通常成功で旧世代を削除する経路はない。

**影響：** 毎回一定量appendして全世代を残すなら累積保存量はO(N²)。現在の小さなfixtureの高速性では長期利用を説明できない。読み側にも線形lookupと二乗sortingがある。

**修正：** まずF09のworkloadで測る。immutable segment共有、generation manifest、reconstructible index等は測定後に比較。正データと捨てられるcacheを明確化。snapshotをpinするreader／backupが存在する前提でretention/GC法則を定める。

**完了条件：** 現在・過去snapshotのreplay、writer/crash/read/GCの組合せがqualified。同じsnapshotがGCで途中消失しない。小さいことを理由にreceipt、fsync、完整性を削らない。

### F11 — backup/restore、format version、migration、portable exportの契約不足【設計不足】

README・公開CLI入口・現行設計資料には、一般利用者が第三者環境で復元できる一連の手順と互換契約が揃っていない。generation IDはformat versionでも内容hashでもない。

**必要な最小設計：**

- 対応OS/FSとlocal writer ownershipの前提。NFS/cloud syncを保証するなら別資格確認。
- 選択generationを固定したbackup、内容検証、別rootへのrestore、restore後doctorとobservable一致。
- schema versionとunknown version拒否。upgrade前backup、dry-run、旧binaryを使う場合の制限。
- importのloss report、ID/correction/measure/provenanceを保存するneutral export。CSVだけを完全backupと呼ばない。
- CURRENT欠損時にどの世代を選ぶか人間に示すrecovery。最大番号の世代を勝手に採用しない。
- retry保証の範囲。現在のexact-candidate照合は主に直後の後継世代との比較であり、他のcommitを挟んだ永続idempotency keyの一般保証ではない。

**完了条件：** clean machineで初期化→記録→backup→元root無しでrestore→query一致を実行。中断migration・ディスク不足・権限不足でも元authorityを失わない。v1公開前に外部互換性の維持期間を明記する。

### F12 — 個人環境へのhard-coded fallbackとpath入力切詰め【静的確認】

**根拠：** `Application.Path_Resolver.Resolve_Paths` の最終fallbackが開発者machineの絶対パス。明示引数と環境変数、CLI commandも `Natural'Min` で切り詰める。`-d` 値なしを解析時に明示拒否しない。

**影響：** OSS利用者の環境で意図しないroot選択／不可解な失敗。明示した識別子やpathを勝手に別値にするのはfail-closedではない。

**修正：** 明示root > documented config/env > 明示的な初期設定、という契約へ。未設定は説明付き拒否または選択画面。入力長超過・欠落は切り詰めず拒否。既存利用者のroot切替は確認付きにする。

**完了条件：** cwd/envの組合せ、長すぎるpath、空env、`-d`のみ、相対root、複数householdで選択が決定的。未知rootでwriterが別の既存authorityへ向かわない。private rootを試験に使わない。

### F13 — parserがrecordの末尾意味を飲み込む可能性【静的確認】

**根拠：** `Storage.Policy_Reader` のversioned ROLE branchは `Count >= 5`、REPLACESは `Count >= 7` と特定tokenの場合だけ扱い、その他の余剰tokenを明示拒否していない（約128〜183行）。

**修正：** 各tagのgrammarを完全消費し、ROLEなら許された5/7 tokenと構造だけadmit。unknown suffix・重複属性・不正REPLACESを拒否。journal/policy/scheduled全grammarのacceptance tableを作る。

**完了条件：** 各正常recordに未知tokenを1個appendしたmutation testが全件拒否。UTF-8不正、空ID、quoted escape、duplicate metadata、巨大行のnegative/round-trip/fuzz specimenを追加。これは実行再現済み項目ではないため、まず小さなparser試験で固定する。

### F14 — Query境界をUIが迂回し、raw storage型がfrontend契約になっている【静的確認】

**根拠：** Home/Actual/Scheduled/Balance/Report TUIがStorage readerをimportし、raw Journal_Result/Policy_ResultをcacheしてProjectへ渡す。ReportのCLI exportもUI.Report_TUIにある。Statement、Frontend_Typesでsnapshot表現も統一されていない。

**修正順：**

1. F08のadmitted snapshot取得をApplicationへ置く。
2. 実際に重複しているReport/Actualの2用途からshared loaded snapshot/sessionを抽出。
3. typed query resultをCLI rendererとTUI rendererへ渡す。
4. 提案、commit、reloadをApplicationに残し、UIはdraft/focus/scrollだけ所有。

HRAのReport_Observationの考え方を使う。ただし全機能を巨大なuniversal query frameworkへ集めない。

**完了条件：** UIからcanonical basename/read APIと会計算術が消え、同一queryをCLI/TUI試験で比較できる。pure Projectのtestabilityとzero-disk-I/O navigationは維持する。

### F15 — 全体資格確認とCIのlogical test集合が一致しない【静的確認】

**根拠：** `tests/test_runner.adb` にTest_Daily_Flow_Query/Test_MoM_Queryがあるが `.github/workflows/qualify.yml` の手書き選択にない。`tools/test-suite` はrunner全体を実行するのでlocalとCIが異なる。`tools/qualify`/CIはformal modelsを実行しない。`proof/hra_n_proof.gpr` はCore中心でApplication/UIはproof対象外。

**影響：** 修正した最新レポートのfocused unitがCIで実行されない。SPARK successをUI計算・filesystem・全modelの保証と誤読しやすい。

**修正：** logical inventoryを一つにし、CIはそれから実行。モデルは変更影響に応じた専用gateとして可視化し、全チェックを走らせたような名称にしない。all testsを単一processへ寄せる場合は既存のprocess状態依存を調査する。

**完了条件：** inventory不一致がCIでfail。今回の反例がそれぞれfocused testとして選択・実行される。証拠表にmodel/tool version/scope/assumptionと具体Ada関数の対応を記録。

### F16 — overflowと例外がtyped refusalへ揃っていない【静的確認】

**根拠：** Budget_WindowはQuanta_Typeで直接集計。Report_TUIはNet_Savings×1000等の倍率計算・backing差を直接実施。Report_TUI.Runは `when others => Stop_Mouse_Scroll` のみで例外を握り潰す。MoMは手動allocation/freeで通常returnのcleanupを所有する。

**注意：** すべての式が実際にoverflow可能と立証したわけではない。bounded入力から各中間式までの保証が不足し、障害が発生した際の伝達が不統一である。

**修正：** report算術をApplication/pure checked projectorへ。representable domain値とrepresentable projectionを分け、Unavailable/Rejectedの診断に変換。予想外の内部例外は端末を復元して明示報告し、正常復帰に見せない。

**完了条件：** admitted最大値近辺、倍率・比率、負数、複数account集計の境界試験。TUI復元後に非成功が分かる。SPARK対象拡張は価値のある算術核に限定する。

## 4. UI：細部まで磨くための具体的課題

### F17 — Actualの「ALL CURRENT」がretained historyを混ぜる【P1・静的確認】

`Application.Actual_Query.Project` は全Journal.Eventsを列挙し、supersessionを除外しない。`UI.Actual_TUI.Draw` は `ALL CURRENT` と表示し、rowはdate/id/descriptionだけ。訂正前後を区別するbadgeもrow型にない。

**方針：** defaultはcurrent frontier、historyは明示toggle。historyではSUPERSEDED/REVERSED、後継へのlinkを表示。reversalはtargetの削除ではなく別eventなので、correctionと同一の除外規則にしない。Homeの日別件数・calendar markerも同じscope意味に揃える。

**完了条件：** 訂正chain、日付を別日へ訂正、reversal越月でlist/count/detail/reportの意味が説明できる。raw historyを消して見かけだけ揃えない。

### F18 — Reportのdrill-downが対象を保持せず、戻ると古い世代を再表示【P1・静的確認】

`UI.Report_TUI.Run` のEnter/aは選択行のaccount/flow日でなく、月初seed＋Actual `Scope_All` を開く。戻りは `Reload` のみで、Current_Pathsを再resolveしない（約1304行）。Actual内で新generationをcommitしてもReportは元generationを読み直す。

**修正：** report行はStringだけでなくdrill targetを持つpresentation rowにする。対象snapshot・period・locus・measureを渡す。childから新snapshot／commit結果を返し、親がそのsnapshotをloadしてfocus/scrollを復元する。

**完了条件：** report明細→対応取引だけ表示→訂正→親へ戻る→同じperiodの新しい値、をPTYで確認。単なる「全Actualを開く」ならdrill-downと呼ばない。

### F19 — mouse lifecycleが入れ子workspaceで壊れる【P1・静的確認】

`UI.TUI_Input` は単一Boolean Mouse_Mode_Started。dispatcher/HomeとReportなどがStartし、Report終了時にStopする。親が継続していてもmouse modeを止められる。

**修正：** terminal sessionの所有者だけがstart/stopするか、明確な入れ子token所有にする。workspace終了をterminal session終了と混同しない。

**完了条件：** Home→Report→Home→Actual→detail→親でwheelが機能し、最終quit/exceptionで必ず無効化。wheel送信がselection/scrollを本当に変えたかassertする。既存PTY成功だけではこの帰還経路の保証にならない。

### F20 — 日本語表示と日本語入力・検索の品質が非対称【P1・静的確認】

- Actualの検索は `Key in 32 .. 126` のASCIIのみ。説明文に日本語を保存できても「昼食」で探せない。
- Line_Editは末尾append/backspaceのみ。Left/Right/Home/End/Delete、cursor位置での挿入がない。
- 最大長超過の入力を無反応で捨てる。Prompt_Forはcancelと空文字を同じ返値にする。
- Reportのpaddingはbyte `S'Length`。emitは140 byteで切り、UTF-8途中切断／長い説明の不可逆な表示欠落を起こし得る。最終端末clipがUnicode対応でも前段の切断は救えない。

**修正：** Unicode input pathとdisplay-column layoutを共有。編集結果はAccepted/Cancelledの判別型。超過時は残容量・警告を出す。grapheme編集の対応範囲も文書化する。

**完了条件：** 日本語のrecord→検索→中間編集→取消→再編集、半角/全角/結合文字/emoji、長文、pasteを同じ経路で試す。検索はdate/amount/locusもtyped filterへ進めるが、まず日本語と既存全文の到達性を直す。

### F21 — layout/help/styleが文字列頼みで狭幅に弱い【P2・静的確認】

Reportは固定table幅と文字列substringでPASS/FAIL等を色付け。7タブbarは横一列。Actual footerも長い固定1行でclipされる。Report_Linesは固定2,048行・140 byteで黙って切る。意味statusが色や文言の偶然に依存する。

**修正：** typed severity/semantic role＋display columns。wide/normal/compactの少数layoutを用意し、helpは利用可能actionsからpack。長い表は必要列優先＋詳細画面へ。color無しでも状態を判別できること。

**完了条件：** 160×45、100×30、80×24、60×20、極小から復帰のsnapshot/PTY。selected、unknown、conflict、disabled、empty、filtered-emptyの区別。light/dark、color無しの手動レビューとNO_COLOR方針。

### F22 — 編集・拒否・競合から立て直すUXがまだ薄い【P1/P2・設計不足】

「guardが拒否する」だけで日常操作は完成しない。各editorで次を共通の受入条件にする：

- field label、現在値、単位、必須／任意、入力例を明示。
- invalid inputは問題fieldを指し、他fieldを失わず修正できる。
- dirty draftをEscで捨てる場合の確認。複数行pasteの改行が次画面のconfirmを勝手に発火しない。
- proposal previewにdate/measure/exact effects/target/correction意味/snapshot。
- stale時は「誰かが変えたので再確認が必要」と説明し、draftを保持して再proposal。自動commitしない。
- commitが成功したが表示reloadだけ失敗した場合、「保存失敗」と言わずreceiptを保持する。
- 禁止actionは理由を示す。internal IDを手入力する代わりにpickerと名称・根拠を表示。

**完了条件：** record/correct/scheduled/capacityの少なくとも4実例で同じinteraction契約。UI kit全面導入ではなく、この反復からfield editor/confirmationを共通化する。

### F23 — 端末故障系と操作の純粋state testが不足【P1・静的確認】

既存PTYは広い正常操作とresize、日本語入力をカバーする。一方、ファイル内にSIGINT/SIGTERM、EOF、termios復元値のassertionは見当たらない。`spec/spin/authority_publication.pml` はwriter publicationモデルで、TUI cancel/reload/terminal restorationモデルではない。

**修正：** signal/EOF/resizeをeditor中・preview中・commit後に注入。raw-mode/mouse/alternate-screen/cursorを復元するsession責任を一箇所へ。keypress→state/actionの純粋transitionを小さく切り出し、PTYはOS接続を確認する層にする。

**完了条件：** cancelは0 facts、EOFでbusy-loopしない、interruptで端末が使用可能、resizeでdraft不変。すべてのworkspaceを長い1本のPTYだけで支えずfocused specimenを追加する。

## 5. 公開OSSとして足りないもの

### F24 — 初回体験、運用手引き、release/security基盤【P1・設計不足】

現READMEは実験段階の位置づけは誠実だが、一般利用者がインストールして10年守るための手引きではまだない。HRA-NにはMIT/Apache licenseとCIがある。ここから先は次の最小セットが必要。

1. **supported environment**：OS、arch、terminal、locale、filesystem、toolchain versions。CIは現在Ubuntu単独。macOSで今回build/PTY成功したことと、release qualificationは区別する。
2. **installation/release**：tagとbinaryの対応、checksum、依存license、再現可能なbuild手順、upgrade/recovery。全依存の供給元とCI action pin方針を記録。
3. **first-run**：合成demo、空rootからlocus/role/zero-origin/windowを設定し、最初の記録・照合・レポートまで進むguide。unknownを消すために偽のZERO-ORIGINを作らせない。
4. **user docs**：keys、concept glossary、JPY-only等の非対応範囲、limits、error recovery、backup/restore。用途別短い手順を優先。
5. **contribution**：small PRの単位、focused feedback、レビュー基準、安定仕様のauthority、issue template。AGENTSだけで人間向け入口を代替しない。
6. **security/privacy**：非公開報告窓口、support logのredaction、umask/file permission、symlink/TOCTOU、terminal escapeを含む入力、巨大file/resource exhaustionのthreat model。これらの脆弱性を今回立証したわけではない。
7. **public contract**：CLI exit、machine output schema、format version、deprecation方針。内部APIを全部固定する必要はない。

**完了条件：** 新規協力者が作者のmachine/path/private dataなしにinstall→demo→record→reconcile→backup→restoreを行える。release checklistで未対応条件を明記。GUI/AIはこの作業の代替にならない。

### F25 — capability matrixのV2が完成度を強く見せすぎる【P1・静的確認】

matrixは多くのgapを正直に記載しているが、ReportsやPolicy administrationのV2は「全surface完了」と読まれやすい。例：Role/WindowのTUI管理は限定的なのに、Policy administration全体にはV2が付く。foundation行のpolicy immutable/writes未接続等の記述は後段の実装状態と食い違う。なおBalance TUIにはassertion入力が実装されており、これを未実装項目に戻してはならない。

**修正：** feature有無、semantic qualification、frontend reach、failure-path qualificationを別セルにする。既知gapを脚注だけに置かない。対象revisionと証拠のscopeを明記し、「同名command」「7 tabs」「SPARK green」をparity判定に使わない。

**完了条件：** この監査の反例が存在する状態で該当能力をcompleteと読めない。Loam比較はobservable単位で、HRA比較も同様。completed一覧を増やすより現行表を修正する。

## 6. Loamの成果を継承する／HRAから救う資産

役割は同一ではないが、知見は双方向に流す。**Loamは本命の進行中設計、HRA-Nはその成果の長期保険かつ独立した探索・相互検証の場、HRAは成熟した法則・操作・部品の資産**である。一般会計OSSの帳票名を追加primitiveの理由にせず、欲しい数字を質問として列挙し、必要な証拠からの導出を検証する。Loamに未実装の質問もHRA-Nで明示的な仮説と合成実験として検討できる。ただし未確定の意味を本番で推測して埋めず、契約と採否を双方で確認する。

下表は初回監査時の入口。各slice開始時に`LOAM_ALIGNMENT.md`の手順で差分を確認し、使う契約・revisionを固定する。

| 欲しい性質 | 比較元の具体的入口 | HRA-Nへ取り込むもの | 持ち込まないもの |
|---|---|---|---|
| household質問から最小意味を決める | `../loam/DESIGN_PHILOSOPHY.md`、`AGENTS.md` | nearby composition check、projectionを正データ化しない判断 | Loamの内部互換自由を公開後HRA-Nへ無条件適用 |
| 同じ期間・訂正frontierで答える | `../loam/Loam/StockFlowReview.lean`、`Loam/Tests/StockFlowReview.lean` | explicit half-open interval、current frontier、start+change=end law | measure/coverage条件を確認せずそのままscalar合計 |
| selected dayとcurrent budgetを分ける | `../loam/docs/TUI.md`、`Loam/Tui/SelectedDay.lean`、`CycleBudget.lean` | Home navigationはpresentation、既知範囲とcurrent windowは別 | 画面日付を動かすと家計の現在まで変わる仕様 |
| terminal layoutを小さく共有 | `../loam/Loam/Tui/Layout.lean`、`Kernel.lean`、`Runtime.lean` | column-aware clip/pad、help packing、pure stateとrenderの分離 | Leanのwidget frameworkをAdaへ丸ごと翻訳 |
| reportをtyped semantic bookにする | `../hra/src/hra-household_report_observation.ads` | rendererへ完成済み観測を渡す、section availability | 旧Household_Stateや8 source topology |
| backingとdaily targetの法則 | `../hra/src/hra-backing_policy.ads`、`hra-cycle_spending_pace.ads` | eligible funding、commitment、available/unavailable、range diagnostic | 全ASSET合計やEnvelope残をsafe cashと呼ぶ近道 |
| 端末・帳票の成熟した小部品 | `../hra/src/hra-terminal_layout.*`、`hra-terminal_selection.*`、`hra-report_table_layout.*`、`hra-report_money_text.*` | layout/selection/money formattingのlawと対応testを比較移植候補に | writer、account名推論、legacy commandの丸ごと再利用 |
| proof境界を説明可能にする | `../hra/docs/PROOF_CORE.md`、HRA-N formal strategy | proof input admission、rangeとexactnessの分離 | 証明数やtool数を品質スコアにすること |

上表のファイルは再利用候補の入口であり、全行の正しさを今回再認定したものではない。HRAのMIT資産をコピーする場合はcopyright/license noticeを保持する。Loamもコード移植前にlicense/権利条件を確認する。**最初に移植すべきものは、型名より法則と反例testである。**

### 推奨する小さな目標境界

```text
Storage bytes
  -> parsed records
  -> shared complete admission
  -> Admitted_Snapshot (identity + evidence)
       -> Actual / Balance / IntervalFlow / Budget / Backing / Pace queries
       -> typed report values (coordinates + per-metric availability)
            -> CLI text / TUI rows / versioned machine adapter

UI draft -> typed intent -> proposal(snapshot)
  -> human confirm -> shared commit -> durable receipt
  -> reload(receipt snapshot) -> restore focus -> render
```

一つの巨大Application façadeも、factごとの別session frameworkも不要。共通化するのはsnapshot取得、診断、interval、publicationといった同じ法則があるmechanics。Relation/Capacity/Physicalの意味まで統合しない。

## 7. 画面別の仕上げチェックリスト

実装済み項目も含む「完成基準」。全部が現在欠落しているという意味ではない。

| surface | 必須の完成状態 |
|---|---|
| 共通chrome | household名、snapshot、観測日/選択日、mode、reload状態。unknown/conflictを色だけに依存せず表示 |
| Home | calendar・件数・Actual listのscopeが一致。attentionは真の全件数。初期化直後は次に必要な設定へ案内 |
| Selected Day | Actual/Scheduledは同居しても別意味。記録seed日を明示。戻った時に元の日・対象を保持 |
| Actual | date/descriptionだけでなく必要なamount/measureのsummary。current/history、検索、filter件数、訂正link、理由付きaction |
| Record/Correction | field navigation、picker、明確な保存と取消、field error、exact preview、stale後draft保持、receipt確認 |
| Scheduled | create/complete/retire/replaceとActualリンク。occurrenceとrecurrence templateを区別。未実装の周期展開を匂わせない |
| Balances/Reconcile | unknownは未知、zeroは根拠付き。実際のbank残をassertionとして入力しdiffを見る経路。調整TXを勝手に生成しない |
| Budget/Capacity | physicalとauthorityを視覚的に分ける。interval、measure、coverage、scheduled pressure。transfer後に元Purposeへ戻る |
| Report | どのmetricもdate/intervalと根拠が明示。unknown metricは非表示/Unavailable。月末一致、typed drill-down、export同値 |
| Policy | Locus/Role/Window/Routeのeffective日、履歴、影響preview。変更不可なら理由とCLI経路を案内 |
| Attention/Relation | 全件到達、closed履歴、due意味、source/settlementへのlink。超過で重要事項が消えない |

使い心地の確認は「作者が知っているキーで動く」だけでなく、初見の人がhelpだけで最初の1件を記録し、間違いを訂正し、銀行残高を照合できるかで行う。

## 8. 他のpitへ渡す実装順

### 各Batchの前後：Loam進捗確認と意味の契約

1. `LOAM_ALIGNMENT.md`とCAPABILITY_MATRIXのcheckpointを読み、local Loam HEAD/branch/dirty状態を確認する。
2. 固定した前回→今回SHAの差分から対象observableに関係するsource/testを確認し、採用／保留／非該当／意図的差異を記す。
3. 今回欲しい数字・操作、最小の保持根拠、期待値・拒否条件を言語中立にする。Loam出力だけを唯一のoracleにしない。
4. HRA-Nで同じ法則を守るための最小変更を行い、合成comparisonとAda/PTY/proofで資格確認する。
5. HRA-Nの正データ探索・実装でLoamへ返せる発見がなかったか確認し、必要なら最小引継ぎpacketを作る。単一のcurrent checkpoint・対象capability・return queueを更新。読取、提案、採用、検証の完了を分ける。

session開始時の軽い確認、関係するsliceの実装/merge前確認、継続開発中の週次レビュー、長期中断後の再確認を行う。background監視の自動化を実装したわけではない。Loamが調査中に更新されても、固定SHAの作業を終えて次回差分として扱う。緊急の誤答封じを上流の完成待ちにしない。

### Batch A — 誤答封じ。大規模refactorなし

1. **F01** 月末反例test→interval正規化。
2. **F02** capacity measure反例test→scalar guardを全入口へ。
3. **F03** role-change反例test→MoM flowを共有flow projectorへ。
4. **F04/F05** metric availability/status/exit contract。
5. **F06** silent truncationを明示拒否へ。paginationは別PRでよい。
6. **F07** SAFE/SOLVENTの誤解を招く断定を止める。正しいfunding queryは別slice。
7. **F15** 上記testがCIで実行されるinventory修正。

各PRは一つの反例とその近隣boundaryに絞る。testの期待値を現在の誤答へ合わせない。

### Batch B — 小さい共有核から同じ意味を導く

8. **F08/F14** 共通admitted snapshot、UI raw reader撤去をReportから開始。Loamのcanonical closure簡約を参考にするが、HRA-Nの境界が同じ保証を持つ前に検査を削らない。
9. **F16** report算術のchecked query化。別の集計engineを作らず、必要なflow/stock/intervalの法則を共有する。
10. **F07** explicit funding/pressureを含むBudget/Paceの契約をLoam/HRAと比較し、CLI/TUI両方で仕上げる。新しい数字ごとに新しい保持stateを追加しない。

### Batch C — 日常操作を一本の流れにする

11. **F17/F18** current/history、typed drill-down、receipt後親reload。
12. **F19/F23** terminal/mouse所有権、EOF/signal/resize。
13. **F20/F22** 日本語検索と共通editor、draft/preview/stale recovery。
14. **F21** compact layout、help、typed styles、手動レビュー。

### Batch D — Loamがなくても継続できる保険

15. **F09/F10** capacityとretentionを圧力に正データ候補を比較→合成10年workload→最小変更。演算のboundednessと履歴の規模を分離する。Loamにも通じる簡約・反例・保持根拠があれば還元する。探索はこのBatchまで禁止するものではなく、関連する各sliceから行ってよい。
16. **F11/F12/F13** backup/restore/schema/root selection/parser grammar。Loam→HRA-Nの明示的移行を合成fixtureで検証し、意味・ID・履歴・description/provenanceを守る。運用切替は別途承認・資格確認が必要。
17. **F24/F25** Loamをbuildできなくても読める仕様・期待値・データ説明、Lean runtime不要のclean Ada build/run、install/release/security、正確なcapability表示。
18. 以上が保険としての優先事項。machine-readable adapter／AI／GUIは実需が出た時に1 query＋1 proposalから追加する。独自feature競争に戻らない。

### 後続pitへのコピー用依頼文

> `AGENTS.md`、`docs/LOAM_ALIGNMENT.md`、現行設計資料と監査Fxxを読む。Loamは開発中の本命、HRA-Nは小さな意味モデルの成果をAda/SPARKで長期維持する保険として扱う。最終checkpointからLoamの進捗を固定SHAで確認し、関係するobservableの契約と採否を記す。HRA-Nでも正データの形と契約の前提を合成実験で探索してよい。新primitiveや重複stateを増やす前に既存根拠から導けないかを確認し、得た反例・簡約・操作改善をLoamへ返せないか検討する。まず合成反例と期待値をfocused testにし、Application/CLI/TUIと必要なstorage/proofまで縦に修正する。HRA/LoamのTUI品質を最低ラインとして磨く。private householdに触れず、writer safetyとunknown/measureの法則を弱めない。Fxxの完了条件と隣接境界を検証し、CAPABILITY_MATRIXのcheckpoint・対象契約・現行仕様を更新する。読取確認、逆提案、採用/資格確認を区別して、実行command/result、未実行項目、意図的差異、Loamへ返す知見（なければ該当なし）、保留と再確認条件を報告する。全面rewrite・万能framework・独自feature競争・実データ自動同期はしない。

## 9. 再現用の最小合成fixture

**必ずTemporaryDirectoryなどの空の使い捨てrootで行う。selected generationや実データを編集しない。** 今回の反例はlegacy read契約も公開されていることからunversioned三streamで確認したもの。versioned経路には後続pitがinitializer＋typed writerまたは専用test fixtureで同じsemantic反例を追加する。

### F01：月末漏れ

`journal.hra`:

```text
TX e0001 2026-09-30 cash:-10 food:10 "month end"
```

`policy.hra`（`scheduled.hra`は空）:

```text
ROLE cash: ASSET
ROLE food: EXPENSE
ZERO-ORIGIN cash:jpy
TRANSFER unallocated Food 100 jpy 2026-09-01
ROUTE food INITIAL MANAGED Food
```

```sh
hra-n -d "$TEMP_ROOT" report --budget -m 9 -y 2026
hra-n -d "$TEMP_ROOT" report --flow -m 9 -y 2026
```

監査時の出力はBudget Food `100 / 0 / 100`、Flow expense `10`。ただし初回掲載fixtureの`ROUTE Food: food`は向きが逆で、月末欠落だけを隔離できていなかった。上記は明示的なfood→Foodへ訂正したfixture。期待はBudget consumption 10、remaining 90。修正前後の独立した再現は`tests/test_cli.py::test_month_end_budget_reports`を参照（月初3に月末16が加わるべきところ、修正前3／修正後19）。現行実装の資格範囲はCAPABILITY_MATRIXのP0に記す。

### F02：foreign capacity

journal/scheduled空、policy:

```text
TRANSFER unallocated Food 100 usd 2026-09-01
```

`report --budget -m 9 -y 2026` が `Unallocated Funds : -100 JPY`、exit 0。期待：JPY限定reportは拒否、またはmeasure別の明示回答。

### F03：分類変更とMoM

journal:

```text
TX e0001 2026-08-10 cash:-10 food:10 "August"
```

policy:

```text
ROLE cash: ASSET
ZERO-ORIGIN cash:jpy
ZERO-ORIGIN food:jpy
ROLE r1 2026-01-01 food EXPENSE
ROLE r2 2026-09-01 food ASSET REPLACES r1
```

9月のMoM：food current 0、Total Expense −10。9月Flow：expense 0。期待：通常支出は9月0、分類変更は必要なら別項目。

### F04：unknown stock

journal:

```text
TX e0001 2026-09-10 cash:-10 food:10 "purchase"
```

policy:

```text
ROLE cash: ASSET
ROLE food: EXPENSE
```

9月MoM：PARTIALとともにNET WORTH −10を表示。期待：stockはUnavailable、retained changeと区別。

### F05：Audit拒否なのにexit 0

上のjournal、policyを `ROLE l0: ASSET` から `ROLE l127: ASSET` の128行だけにする。cash/foodはそれらに含めない。

```sh
hra-n -d "$TEMP_ROOT" report --audit -m 9 -y 2026
# 監査時: [ERROR] Audit projection rejected / exit 0
```

### F06：65件目のAttention

journal/scheduled空、policyを次の65行にする：

```text
ATTENTION a0001 "synthetic-1" nodue
...
ATTENTION a0065 "synthetic-65" nodue
```

`attention` は `HRA-N Attention ( 64 open)`、a0065なし、exit 0。期待：65件全件到達、または明示的な上限拒否。

### F08：三streamの意味の検査が不一致

F04のfixtureへ `ZERO-ORIGIN cash:jpy` を追加し、scheduledだけ `INVALID` とする。`doctor` はScheduled Life FAIL・exit 1、9月 `report --audit` は複数PASS・exit 0。

## 10. 小さな核の「長期保険」として成功した状態

Loamの成功はまだ前提にせず、進捗とともに契約を磨く。HRA-Nも行数だけで成功を宣言しない。次を満たせば、独自機能を増やすより保険として磨き続ける価値がある。

- Loamで確かめた数字と操作を、固定契約・合成期待値・差異の説明とともにAda/SPARKで引き継げる。
- 欲しい答えの数だけCore概念を増やさず、少ない独立事実と共通法則から豊かなprojectionを導く。
- HRA-Nでも正データ候補と共通前提を検証し、その反例・簡約をLoamへ返して双方を改善できる。
- 将来Loamのtoolchainを使えなくても仕様とデータが読め、HRA-Nを独立してbuild/runし、明示的に移行・復元できる。

- 同じsnapshotと座標への答えが、CLI/TUI/後続adapterで一致する。
- 不明、不足、競合、上限、非対応を隠さない。失敗から利用者が回復できる。
- 10年分を追加しても、記録・照合・訂正・復元が止まらない。
- 作者以外が入手・build・試験・backup/restoreできる。
- 日本語の日常操作が浅く、速く、取り消せ、根拠へ辿れる。
- 保存仕様と互換の約束が小さく明確で、依存や作者の環境が変わっても読める。
- 大きな新機能がなくても、small change→反例→test→改善の循環が続く。

**最優先は「Loamと別に多機能さを競う」ことではなく、「小さい核から豊かな答えを導く成果を別基盤で長期間守り、独立して考え直すことでLoamにも良い発見を返す」ことである。既存の核を活かし、正データの形も模索し、定期的な双方向の検証で意味・データ・操作の継続性を磨く。**
