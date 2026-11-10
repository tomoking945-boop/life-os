#!/usr/bin/env python3
"""公開データセット CORD で、合計金額の決め方を Mac の中だけで評価する（Build 22）。

docs/BUILD_22_KEYBOARD_AND_RECEIPT_NUMBER_ACCURACY.md の「公開データセット」を参照。

- CORD（Clova AI。インドネシアのレシート。ライセンス CC BY 4.0）の **注釈の JSON だけ** を使う（画像は読まない）。
  注釈の valid_line（単語・位置・行番号）を、アプリと同じ形の「文字の行」にして、
  receipt_eval.py の Build 21／Build 22 の決め方に通し、gt_parse.total.total_price と比べる
- データは Mac の中の evaluation/datasets/（.gitignore 済み）に置く。アプリにもリポジトリにも入れない
- 結果は件数だけを出す（店名・商品名・金額・文字は出さない）
- 日本のレシートとは別に数える。CORD の結果に合わせて日本向けの決まりを変えない
- ネットワークは使わない

使い方：
  python3 tools/receipt-eval/cord_eval.py evaluation/datasets/cord/json
  （CORD v0 の json フォルダ、または Hugging Face 版の ground_truth を1件ずつ .json に保存したフォルダ）
"""

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import receipt_eval  # noqa: E402


def rupiah(text):
    """「60.000」「60,000」「Rp 60.000」を整数にする（読めなければ None）"""
    if text is None:
        return None
    digits = re.sub(r'[^0-9]', '', str(text))
    return int(digits) if digits else None


def lines_from(annotation):
    """注釈の valid_line を、行ごとの「文字・位置」にする（同じ row_id の単語を左から並べる）"""
    meta = annotation.get('meta') or {}
    size = meta.get('image_size') or {}
    width = float(size.get('width') or 0) or None
    height = float(size.get('height') or 0) or None
    rows = {}
    for line in annotation.get('valid_line') or []:
        for word in line.get('words') or []:
            text = (word.get('text') or '').strip()
            quad = word.get('quad') or {}
            if not text or not quad:
                continue
            xs = [quad.get(k, 0) for k in ('x1', 'x2', 'x3', 'x4')]
            ys = [quad.get(k, 0) for k in ('y1', 'y2', 'y3', 'y4')]
            rows.setdefault(word.get('row_id', id(word)), []).append((min(xs), min(ys), max(xs), max(ys), text))
    result = []
    for words in rows.values():
        words.sort(key=lambda w: w[0])
        x0 = min(w[0] for w in words)
        y0 = min(w[1] for w in words)
        x1 = max(w[2] for w in words)
        y1 = max(w[3] for w in words)
        entry = {'text': ' '.join(w[4] for w in words), 'c': 1.0}
        if width and height:
            entry.update({'x': x0 / width, 'y': y0 / height, 'w': (x1 - x0) / width, 'h': max(y1 - y0, 1) / height})
        result.append(entry)
    result.sort(key=lambda e: e.get('y', 0))
    if not (width and height):
        result = [e['text'] for e in result]
    return result


def expected_total(annotation):
    parse = annotation.get('gt_parse') or {}
    total = parse.get('total') or {}
    if isinstance(total, list):
        total = total[0] if total else {}
    return rupiah(total.get('total_price'))


def load(path):
    with open(path, encoding='utf-8') as handle:
        data = json.load(handle)
    # Hugging Face 版は {"ground_truth": "<JSON の文字>"} の形
    if isinstance(data, dict) and isinstance(data.get('ground_truth'), str):
        data = json.loads(data['ground_truth'])
    return data


def main(folder):
    files = sorted(name for name in os.listdir(folder) if name.endswith('.json'))
    counts = {'old': {'ok': 0, 'wrong': 0, 'empty': 0}, 'new': {'ok': 0, 'wrong': 0, 'empty': 0}}
    used = 0
    for name in files:
        annotation = load(os.path.join(folder, name))
        expected = expected_total(annotation)
        if expected is None:
            continue
        used += 1
        lines = lines_from(annotation)
        for version, new in (('old', False), ('new', True)):
            amount = receipt_eval.extract(lines, new)['amount']
            if amount is None:
                counts[version]['empty'] += 1
            elif amount == expected:
                counts[version]['ok'] += 1
            else:
                counts[version]['wrong'] += 1
    print(f'CORD（合計の正解がある注釈）：{used} 件（画像は使っていない）')
    for version, label in (('old', 'Build 21'), ('new', 'Build 22')):
        c = counts[version]
        print(f'{label}：正しい {c["ok"]}・間違った金額を入れた {c["wrong"]}・空 {c["empty"]}')
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 2 or not os.path.isdir(sys.argv[1]):
        print('使い方：python3 tools/receipt-eval/cord_eval.py <CORD の注釈 JSON のフォルダ>')
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
