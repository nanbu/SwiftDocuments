# SwiftDocuments

- セッションの入口は `~/.claude/CLAUDE.md`。
- API・読み取り契約の正典は `docs/implementation-spec.md`。仕様を先に改訂してから実装する。
- 共通モデルは DocumentCore、Word 固有の解釈は DocumentDOCX。Word の XML 名を共通 API の名前にしない。
- 未対応要素は警告にする。読み取り失敗を成功や空文書に変えない。テストを弱めて通さない。
- 新しい読み取り動作には仕様に対応するテストを付ける。`swift test` と `swift build -c release` を検証の基本にする。
- 実アプリ由来の fixture は架空の内容に限定。生成スクリプトと出典を残す。
- README の対応表と実装の差は `scripts/check-contract.py` で検査する。
- 性能は同一操作の時間とメモリを併記。測定していない環境や挙動を対応済みと呼ばない。
- 公開・リリースは依頼があったときだけ。Conventional Commits を使う。
