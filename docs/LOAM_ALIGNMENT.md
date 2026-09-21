# Loamとの相互検証・正データ探索・長期保険設計

Status: **HRA-Nのproduct objectiveとLoam比較手順の現行authority**

## 1. 本命と保険

- **Loamが本命。** 小さな概念・保持事実・機能・部品から、一般的な会計／家計簿OSSが答えられる豊かな数字と日常操作を導く研究・実用系。現在も開発中であり、完成・凍結済みとは扱わない。
- **HRA-NはAda＋SPARKによる長期利用の保険であり、独立した設計探索・相互検証の場でもある。** Loamで確かめた意味と操作を別基盤で維持しつつ、正データの形・最小の保持根拠・admission境界をHRA-Nでも模索する。Loamへの一方向の移植や凍結コピーに限定しない。無根拠な意味の分岐やfeature競争は避けるが、根拠付きの代替設計は歓迎する。
- **HRAは資産・比較元。** 会計の法則、レポート観測、端末部品、試験を活かす。旧source topologyやontologyを自動的に継承しない。
- 現在の日常記帳authorityはLoam。保険開発は運用切替の指示ではなく、並行記帳・自動同期・実データの再生成を伴わない。

Lean 4の将来のtoolchain/API保守負担への不安が、実装基盤を分散する動機である。Lean 4の衰退や不安定化を予言するものでも、Adaなら無条件に永続利用できると保証するものでもない。

保険の成立条件は言語名ではなく、**読める仕様とデータ、同値性の証拠、独立したbuild/run、履歴を守る移行と復元、引き継げる日常TUI**である。HRA-Nのproduction runtime/buildにLeanを必須依存として持ち込まない。比較開発時にLoamを実行することとは分ける。

## 2. 小さい核から豊かにするとは

優先順位は次のとおり：

1. 必要な質問へ正しい答え、または根拠付きの不明／拒否を返せる。
2. 独立して保持する意味・事実が少なく、authorityが明確。
3. 同じ法則を一度だけ実装し、projectionとUIで再利用する。
4. 保存・復旧・検証・日常操作を第三者が理解できる。
5. その条件下で部品・依存・コード量を減らす。

「小さい」はCoreディレクトリの行数だけではない。Application/UI/Storageへ計算と状態を追い出してCoreだけ小さくしても達成ではない。少ない型の巨大record、全用途共通の万能event、巨大generic frameworkも自動的に簡潔とはならない。

新しいprimitive／保持field／queryごとに問う：

- これがないと、どのobservableを区別できないか。
- 今ある事実から再構成できないか。できるならprojectionにできないか。
- 独立した意味を形が同じという理由だけで混ぜていないか。
- parser/admissionが保証した法則を別層で再実装していないか。
- 信頼できる境界での検査と、型により不要になった再検査を区別したか。
- 純粋なbounded演算の制限を、生涯の履歴上限にしていないか。

一般的な会計／家計簿の数字は**質問の受入基準**であって、同じ数だけCore概念を作る指示ではない。残高、収支、期間比較、予算残、予定支払、資金裏付けなどは、必要な根拠と区間がある場合に導く。未知のopening、分類、価格、coverageを推測して「対応した」ことにしない。

## 2A. Core境界監査: primitive / retained / interpretation / derived

この分類はHRA-N `d4dbf4de459343df00e86d77ae32f3c71583563f` と、比較時点の
Loam `c7df424d0f5c4b7f9d073e00948ad6cc69560b47` を対象にした
**責務分類**である。ファイル配置の即時変更、Loam sourceの逐語移植、
既存の意味の削除を承認するものではない。

Coreを小さくする時は、ファイル数ではなく次の四層を区別する。

| 層 | 意味 |
|---|---|
| **primitive** | 他の家計意味を前提にせず、identity・quantity・effect・保存則などを表す最小機構 |
| **retained** | 他の保持事実から再構成できず、失うと二つの家計履歴を区別できなくなる証拠 |
| **interpretation** | retained factsをあるsnapshot/effective coordinateでどう受理・分類・経路付けするかという権威 |
| **derived** | retained / interpretation から再計算できる残高、open状態、summary等。canonical stateとして二重保持しない |

一つのpackageが複数層を含み得る。分類単位はpackage名ではなく、型・事実・法則・queryの責務である。

### 現行Coreの分類

| package | 主分類 | 監査結果 / 次の問い |
|---|---|---|
| `Types` | primitive | `Locus_Id`, `Measure_Id`, `Event_Id`, identity tokenは小さい。bounded token長はAda実装制約であり家計意味ではない。 |
| `Quantity` | primitive | exact signed quantityとoverflow-safe arithmetic。保持意味を増やさない。 |
| `Movement` | primitive **候補** | 保存則はprimitiveに値するが、`Movement_Change.Coordinate : Locus_Id` と「2 participants以上」がLocus固有admissionを代数へ混ぜる。Loam同様、座標型から独立したbalance lawへできるか検証する。 |
| `Event` | primitive / retained境界 | Event identityとEffectsは核。ただし全Effectに `Effect_Key` を要求する点は、identityを必要時だけ保持する現行Loamより重い。匿名Effectを許してobservableを失わないか検証する。 |
| `Validity` | primitive + retained | calendar arithmeticと「Eventがいつ起きたか」の独立証拠、さらにcorrection historyが同居する。日付機構とoccurrence evidenceを分離できる。 |
| `Description` | retained | narrativeはEffectから復元不能。独立保持する根拠がある。 |
| `Assertion` | retained | observed balanceはmovement historyから自動推論できない独立証拠。 |
| `Attention` | retained | financial occurrenceが存在しなくても残すべきmatterを表すため、他planeから導出不能。open/closed query自体はderived。 |
| `Relation` | retained | debtor/creditor/face/source/discharge provenanceはphysical Effectsだけでは復元不能。`Remaining_For` 等はderived。 |
| `Capacity` | retained + derived | allocation/transfer factsは独立意味を持つ一方、独自 `Capacity_Change` とconservation計算はgeneric balance lawとの重複候補。`Entitlement_At` はderived。 |
| `Scheduled` | retained + derived | occurrenceとcompletion/retirement/replacementは保持証拠。`Is_Current_Open` はderived。独自 `Scheduled_Change` はgeneric balance law再利用候補。 |
| `Transaction_Metadata` | retained evidence bundle | purpose / replaces / reverses / relation / dischargeという別authorityを一recordへ束ねる。便利なtransport shapeがsemantic authorityになっていないか監査し、独立fact familyへ分解またはadapterへ降ろせるか調べる。 |
| `Admission` | interpretation | Locusの存在ではなく「新規writeで使用可能か」を決める現在policy。Locus primitiveとは分離を維持する。 |
| `Actual_Routing` | retained interpretation | (locus, effective) のrouting assertion自体は保持証拠。as-of purposeはderived interpretation。 |
| `Accounting_Role` | retained interpretation + derived | effective role assignmentは保持policy。`Financial_Summary`, net worth/savings, completeness等はprojectionなので同package内でもderived側として扱う。 |
| `Coverage` | retained epistemic + derived | known-zero origin coverageは独立証拠。ただしneutral `Coordinate_Type = (Locus, Measure)` をCoverageが所有しているため、kernel側のEffect coordinateへ昇格できるか検証する。`Balance_Result` はderived query結果。 |
| `Window_Policy` | interpretation / retained policy候補 | user-defined named intervalなら独立policy。単なる月次・cycle intervalなら日付から導出できるので保持しない。具体的に区別できなくなる履歴がある場合だけretainedに残す。 |

### 今回の監査で見つかった優先整理候補

1. **balance lawをLocusから切り離す。**  
   `MovementChange Coordinate` 相当をAda/SPARKで表現できる最小設計を比較し、
   Actual / Capacity / Scheduled が同じ保存則を共有できるか確認する。
   「最低2点」などのdomain admissionはgeneric zero-sum lawの外へ置く候補とする。

2. **Effect identityを必要な時だけ保持できるか調べる。**  
   現行HRA-Nは全Effectにstable keyを要求する。Relation等が参照するEffectだけを
   identifyして、普通のEffectに不要なidentity stateを持たせず同じobservableを保てるか
   合成fixtureで比較する。

3. **neutral coordinateのauthorityをCoverageから外す。**  
   `(Locus, Measure)` はcoverage固有概念ではない。Event/Effect projection、
   assertion、coverageが共有する最小coordinate型として置けるか確認する。

4. **保持事実とprojectionをpackage内でも分けて数える。**  
   AccountingRoleのFinancialSummary、Relationのremaining、
   Scheduledのcurrent-open、Capacityのentitlement等を、新しいcanonical factとして
   重複保持しない。

5. **大きな混合packageを分解候補として監査する。**  
   `Validity` はcalendar / occurrence / correction、
   `Transaction_Metadata` はpurpose / replacement / reversal / relation / dischargeを
   一緒に持つ。まずobservableを失う最小反例を探し、分離できる部分だけを分ける。

6. **Windowは「設定だから保持」ではなく不可逆情報で判定する。**  
   月初/月末など既知calendar lawから作れる窓はderived。
   household固有のnamed intervalだけがretained policy候補になる。

この監査の目標はLoamと同じfile topologyにすることではない。
HRA-N側で独立に同じobservableを説明した時、より少ないsemantic authorityで済むなら
その簡約を採用候補にする。逆に、Ada/SPARK側の明示性によってLoam側の隠れた前提が
見つかった場合は、LOAM_ALIGNMENTのreverse-feedback手順で返す。

**次の実装slice:** まず `Movement` のgeneric化可能性だけを扱う。
他の候補を同時に移動しない。現行APIとfixtureから、保存則そのものと
Locus固有admissionを分離できることを示してからproduction codeを変更する。


## 3. 相互検証の単位は意味の契約

```text
Loamの設計・実装・反例・試験
       ⇅ 確認／提案／反例／簡約を返す
言語中立のobservable契約と合成specimen
       ⇅ 同じ答えを保てるか／契約自体に不足がないか
HRA-Nの正データ候補・Ada/SPARK実装・検証
       ↓
CLI/TUI、保存、移行・復元
```

Loamのcommit、package名、ファイル数、型の配置をそのまま翻訳しない。**HRA-Nの正データ形式は探索対象**であり、Loamの形にも現行の三stream/generationにも固定しない。守るのは必要な家計事実と説明可能な法則。形式を変える際は独立したqualified transitionとして扱う。

契約は比較中の基準点であって、疑ってはいけない最終解ではない。反例で契約の不足が見つかったら、旧期待値への無理な一致より、欠けた前提・保持根拠・修正案を明示して両側で見直す。双方の採用判断が済むまでは差異を公開し、parityと呼ばない。

### 各sliceに必要な契約

既存のCAPABILITY_MATRIXと該当test/仕様に次を置く。別の一般仕様システムは先回りして作らない。

| 項目 | 必須内容 |
|---|---|
| Observable | 利用者の質問、返す数字／状態／操作 |
| Source reference | Loamの固定SHA、対象関数・test、HRA等の比較元 |
| Retained evidence | 独立に必要な事実、導出可能な値、coverage |
| Coordinates | snapshot、effective日/interval、measure、Role/Route等の評価時点 |
| Law | 集計式、correction/reversal、保存則、丸め／範囲 |
| Failure | unknown/conflict/unsupported/overflow/staleの意味 |
| Synthetic evidence | 正常・反例・境界、期待値の根拠、実行command/result |
| HRA-N mapping | admission/query/intent、CLI/TUI、storage、proofの対応 |
| Adoption decision | 採用対象／保留／非該当／意図的差異、理由、再検討条件 |
| Reverse feedback | HRA-Nで得た反例／簡約／正データ候補、Loamへの適用条件、提案・検証・採否の状態 |

Loam出力を唯一のoracleにしない。期待値は仕様・手計算・法則からも固定する。両者が同じ誤答ならparityでも不合格。LoamとHRAの意味が違う場合はその差を質問として解決し、都合のよい合計だけを比較しない。

保存形式やIDの生成法が違ってもよい。ただしidentity対応を明示し、履歴・参照・description/provenanceの欠落を正規化で隠さない。SPARKの有限範囲とLeanの整数範囲の差も契約へ出す。比較器は値を読み替える薄いadapterとし、第三の会計エンジンを実装しない。

### 正データの形を探索する手順

1. **具体的な圧力を一つ選ぶ。** 人間に読めない、同じ事実を二重保持、履歴容量、跨stream参照、import loss、proofしづらさ、復旧の複雑さなど。名称変更だけを探索成果にしない。
2. 現行形と、圧力に応える最小の代替形を比較する。独立事実の分け方、identity/reference、時系列、encoding、ファイル分割、publication単位、index/cacheを区別する。全部を一度に変えない。
3. 同じ合成履歴から同じobservableを再構成できるか試す。保持すべき意味と捨ててよい派生物を明示し、訂正・unknown・measure・provenanceを省略して簡単にしない。
4. 読みやすさ、編集/取込の安全性、行数・重複、disk/load/commit、proof/admission、crash/recovery、migrationの負担を比較する。Ada固有の利点とLoamにも通じる利点を分ける。
5. 候補を採用／棄却／保留にする。候補は合成fixtureや隔離された実験で評価し、実データやCURRENTは触らない。本番cutoverは別途承認とqualificationを得る。

現行writer guardは現行authorityに対して引き続き有効。新形式の探索許可を、選択generationの直接変更や二つの運用authorityを維持する許可に読み替えない。旧snapshotの意味を保つ読み方／移行手順とrollback可能性を先に示す。

### HRA-NからLoamへ発見を返す

各sliceで一度、**「この比較でLoamの前提・保持事実・部品を小さく／明快にできないか」**を確認する。成果の件数をquotaにしない。具体的な発見がなければ「該当なし、確認した境界」を短く記す。

- 同じソースを逐語翻訳するより、同じ契約へ異なる表現を当てて、共有してしまった盲点を見つける。
- Ada/SPARKで困るrange、所有権、closure、publication単位は、単なる移植の不便か、言語に依存しない意味の問題かを切り分ける。
- 保持fieldの削除候補は、そのfieldを失うと区別できなくなる二つの履歴がないかを探す。安全性のために必要なら削らない。
- 不一致はHRA-N不具合／Loam不具合／契約不足／意図的範囲差をまず未確定として調査する。Loamへ合わせるだけでも、Ada側が常に正しいとするのでもない。

**Loamへの引継ぎpacket：**

| 項目 | 必須内容 |
|---|---|
| Question | 改善したいobservable／正データ上の圧力 |
| References | 両repoの固定SHA、対象関数・model・test |
| Hypothesis | 代替表現・削除可能なstate・契約修正案と、その前提 |
| Smallest evidence | 公開可能な最小合成fixture／反例、期待値、command/result、未検証範囲 |
| Trade-off | 意味の保持、拒否条件、簡約効果、追加負担、migrationの必要性 |
| Loam relevance | Loamにも適用できる法則か、Ada固有の実装都合か |
| Decision | 未提案／提案済み／検証中／採用／保留／不採用、理由と次の確認 |

packetは該当する現行仕様・test・issue/PR等への参照でまとめ、未解決状態だけをCAPABILITY_MATRIXのreturn queueへ置く。独立した発見がある時に、Loam側の方針に従ってobservation/test/小さな提案へ渡す。HRA-Nのtaskだけを理由にLoamや実データへ自動変更しない。

Loam側で受け入れられたら採用SHAと証拠を確認し、次回のLoamレビューでHRA-Nにも再評価する。**発見→逆提案→Loam側検証→必要なら双方の契約更新**までを循環とする。提案作成だけを採用や検証成功と呼ばない。

## 4. 定期的なLoam確認

### 実施タイミング

- HRA-Nの各作業session開始時に、Loamのbranch/HEAD/working treeと最終確認SHAとの差を軽く確認する。
- 影響するLoam変更があれば、そのHRA-N sliceの実装前とmerge前にfocused reviewする。
- 継続開発中は**少なくとも週1回**、未分類差分・保留項目・HRA-NからLoamへのreturn queueを見直す。長期中断後は再開時に実施。
- format/authority/correction/coverage/funding/receiptの変更は、週次まで放置せず影響する作業を止めて確認する。緊急の誤答封じまで無関係な上流開発待ちにしない。
- release・移行・復元訓練前は比較対象を固定し、未採用差分と互換範囲を明記する。

これはpitの作業手順であり、background監視や自動実行schedulerを設置したという意味ではない。作業していない期間の自動追従は保証しない。

### 最小手順

1. `AGENTS.md`、本書、CAPABILITY_MATRIXの現在の比較checkpointを読む。
2. Loamの`AGENTS.md`、`README.md`、`DESIGN_PHILOSOPHY.md`、`docs/HOUSEHOLD_OPERATING_MODE.md`、変更領域の現行docsを確認する。
3. ローカルbranch/dirty状態と**固定SHA**を取得。調査中に別pitがLoamを進めても、その回の差分は固定SHAで読む。dirty変更はcommit済みproductionと分け、勝手にcheckout/reset/stashしない。
4. 前回確認SHA→今回SHAのlogとname-only diffから分類し、関係するsource/testsだけ精読する。履歴は差分発見に使い、現行仕様の代用にしない。
5. 新しい意味、同じ意味の簡約、admission強化、TUI改善、保存互換、test移動、未確定研究を分ける。
6. 合成反例とLoam側のfocused evidence/CIを確認。CI未取得、未実行ならそのまま記録する。最新HEADやmerge済みだけでqualifiedとはしない。
7. 採用／保留／非該当／意図的差異を決め、HRA-Nの対象sliceと次の検証を書く。比較可能な面が変わるまで全面移植しない。HRA-Nでの探索がLoamへ返せる発見になったかも確認し、必要ならpacketとreturn queueを更新する。
8. CAPABILITY_MATRIXの**単一のcurrent checkpointと未解決項目**を更新。各週の別日誌や完了一覧を増やさない。auditの過去再現SHAは新SHAで上書きしない。

ローカル確認例（`FROM`はcheckpoint、`TO`は取得後固定したSHA）：

```sh
rtk git -C ../loam status --short
rtk git -C ../loam branch --show-current
rtk git -C ../loam rev-parse HEAD
rtk git -C ../loam log --oneline "$FROM..$TO"
rtk git -C ../loam diff --name-only "$FROM" "$TO"
rtk git -C ../loam diff "$FROM" "$TO" -- <relevant-source-and-tests>
```

ローカル確認だけなら「remote最新まで確認」と書かない。必要でnetworkが使える場合は通常のfetch/CI照会でremote tipと比較し、branchを勝手に更新・mergeしない。取得不能なら最後に確認できた範囲を明記する。

### 変更の採否

- **同じ意味の簡約：** 既存admissionから導ける補助stateや重複検査の撤去候補。ただしHRA-Nでも前提が成立することを先に証明／試験する。
- **意味・数字の変更：** 期待値の変更理由を確認。Loam自体の反例を調べ、双方の契約を直す。単なるgolden再生成は禁止。
- **TUI改善：** 同じfixture・操作・端末条件で比較し、機能だけでなく情報順位・状態復帰まで採用する。
- **保存形式変更：** 意味の変化とencodingだけの変化を分ける。HRA-Nのformatを毎回追随renameしない。
- **実験：** 上流実験のproduction追従はqualified evidenceが揃うまで保留できる。HRA-N自身の正データ・意味の仮説の探索はLoamの先行採用を必要としない。探索と本番採用を分ける。
- **HRA-N固有の保険要件：** durability、独立build、bounded safety、backup/restore、長期容量の差異は理由付きで維持できる。Loamにないこと自体は禁止理由ではない。

## 5. 小ささと保険の受入基準

### 比較するもの

- 同じobservable集合、正常／拒否範囲、日常TUI操作、10年workload。
- 独立に保持する意味の数、導出値の重複保持、reader/publisher/計算経路の重複。
- Coreだけでなくproduction全体、UI、storage、tests/proof、依存と運用手順。
- cold load/commit/memory/diskとwarm navigation。容量限界も比較条件に入れる。

コード行数はこの後に測る。AdaとLeanの構文差を無視した固定削減率を合否基準にしない。未実装機能や試験を消して縮小率を作らない。上限・proof・diagnostic・crash safetyを守ったまま簡約する。

### 保険としての最低gate

1. 選んだLoam契約を、HRA-Nが同じ合成specimenで回答・拒否できる。
2. その仕様・fixture・データ説明を、将来Loamをbuildできなくても読める。
3. HRA-NをLean runtimeなしのclean環境でbuild/runできる。
4. Loamからの明示的export/importでidentity/history/measure/provenanceを守り、移行後のobservableが一致する。現時点で完成したbridgeがあるとは主張しない。
5. 別rootへのbackup/restore、10年履歴、TUIでの記録・訂正・照合をqualifiedにする。
6. GUI/AIなしでもこの継続利用が成立する。外部adapterは実需から後で追加する。

運用切替は別の利用者判断とqualificationが必要。比較試験の成功だけでLoamへの日常記帳を止めない。

## 6. 後続pitの開始・終了契約

開始時は「今回比較するobservable／疑う前提」「両側の比較SHA」「正データ候補と独立した意味を増やす必要の有無」「現在のaudit反例」「選んだ最小feedback」を短く示す。

終了時は、採否・差異・合成testの結果・未実行項目・HRA-Nの新しい境界・Loamへ返せる発見（なければ該当なし）・次回確認対象を示す。CAPABILITY_MATRIXのcheckpoint、return queue、採用済み契約のqualificationは別の状態として更新する。

読んだだけの変更を「追従完了」、局所test成功を「全面互換」、proof successを「長期保険完成」と呼ばない。
