PDF に日本語・中国語を出すためのフォントをここに置く。

なぜ必要か
  package:pdf は端末にインストールされたフォントを使えない。PDF に埋め込む
  ため、TTF ファイルをアプリに同梱する必要がある。無いと日本語が全部
  豆腐(□□□)になる。

無くても動く
  フォントが見つからない場合、書き出しは英字ラベルの PDF になる。
  「フォントが無いので書き出せません」で止めるより、読める形で出すほうが
  ましなので、そうしてある。CSV は影響を受けない(中身は英語の列名)。

置くファイル名（この順で探す）
  assets/fonts/NotoSansJP-Regular.ttf
  assets/fonts/NotoSansSC-Regular.ttf

取得（Mac のプロジェクト直下で実行）
  curl -L -o assets/fonts/NotoSansJP-Regular.ttf \
    "https://raw.githubusercontent.com/google/fonts/main/ofl/notosansjp/NotoSansJP%5Bwght%5D.ttf"

  うまく表示されなかったら、こちらの静的フォントで試す:
  curl -L -o assets/fonts/NotoSansJP-Regular.ttf \
    "https://raw.githubusercontent.com/google/fonts/main/ofl/mplus1p/MPLUS1p-Regular.ttf"

注意
  * .otf は使えない。package:pdf は glyf 形式の TrueType のみ。
  * ファイルを置いたら flutter clean は不要。flutter run で入る。
  * 中国語(簡体字)の PDF が必要になったら NotoSansSC も置く。日本語フォント
    だけだと一部の簡体字が出ない。
