#!/usr/bin/env python3
"""レシートの数字の読み取りの評価（Build 22。docs/BUILD_22_KEYBOARD_AND_RECEIPT_NUMBER_ACCURACY.md）

アプリ（Swift）の ReceiptFieldExtractor・ReceiptLayout・ReceiptNumberText の「合計金額」と「商品明細」の決め方を、
Python に書き写したもの（評価用の写し。アプリの中では動かない）。Build 21 の決め方（old）と Build 22 の決め方（new）を、
日本向けの合成レシート（LifeOSTests/Fixtures/JapaneseSyntheticReceipts.json）で比べる。

- 実在のレシート・公開データセットは含まない（ネット接続も使わない）
- 読み取りそのもの（Apple Vision）は写していない。合成レシートの「読み取った文字」から先の計算だけを比べる
- アプリの決め方を変えたら、この写しも同じように直す（Swift のテスト Build22ReceiptNumberAccuracyTests が同じ合成レシートで確かめる）

使い方：python3 tools/receipt-eval/receipt_eval.py [合成レシートの JSON]
"""
import datetime
import json
import os
import re
import sys

MAX_AMOUNT = 999_999_999


# MARK: - 文字の整え

def normalize(text):
    out = []
    for ch in text:
        v = ord(ch)
        if 0xFF01 <= v <= 0xFF5E:
            out.append(chr(v - 0xFEE0))
        elif v == 0x3000:
            out.append(' ')
        else:
            out.append(ch)
    return ''.join(out).strip().replace('￥', '¥').replace('\\', '¥')


CONFUSABLES = {'O': '0', 'o': '0', 'I': '1', 'l': '1', '|': '1', 'Z': '2', 'z': '2', 'S': '5', 's': '5', 'G': '6', 'B': '8'}
TOKEN = r'[0-9OoIl|ZzSsGB](?:[0-9OoIl|ZzSsGB,.]*[0-9OoIl|ZzSsGB])?'


def repaired_token(token, mostly_digits):
    digits = sum(1 for c in token if c.isascii() and c.isdigit())
    letters = sum(1 for c in token if c in CONFUSABLES)
    if digits < 1:
        return None
    if mostly_digits:
        if digits < 2 or letters > 1:
            return None
    elif letters > digits:
        return None
    fixed = ''.join(CONFUSABLES.get(c, c) for c in token)
    if re.fullmatch(r'\d{1,3}(\.\d{3})+', fixed):
        fixed = fixed.replace('.', ',')
    return fixed


def _repair_tokens(text, pattern, group, mostly_digits):
    result = text
    for m in reversed(list(re.finditer(pattern, text))):
        start, end = m.span(group)
        original = text[start:end]
        fixed = repaired_token(original, mostly_digits)
        if fixed is None or fixed == original:
            continue
        result = result[:start] + fixed + result[end:]
    return result


def repaired(text):
    r = _repair_tokens(text, r'(¥\s*)(' + TOKEN + r')(?![A-Za-z])', 2, False)
    r = _repair_tokens(r, r'(?<![A-Za-z0-9])(' + TOKEN + r')(\s*円)', 1, False)
    r = _repair_tokens(r, r'(?:(?<=\s)|^)(' + TOKEN + r')(?=\s*[※*★軽外内非]*\s*$)', 1, True)
    r = re.sub(r'(\d),\s+(\d{3})(?!\d)', r'\1,\2', r)
    r = re.sub(r'(¥\s*\d{1,3})\s(\d{3})(?![\d,])', r'\1,\2', r)
    return r


def discount_amount(text):
    t = text.replace('▲', '-').replace('△', '-').replace('−', '-')
    last = None
    for m in re.finditer(r'-?\s*¥?\s*(\d{1,3}(?:,\d{3})+|\d+)\s*円?-?', t):
        after = t[m.end()] if m.end() < len(t) else ''
        if after in ('%', '点', '個'):
            continue
        raw = m.group(1).replace(',', '')
        if len(raw) > 9:
            continue
        v = int(raw)
        if 1 <= v <= MAX_AMOUNT:
            last = v
    return last


# MARK: - 行

class Row:
    def __init__(self, text, confidence=1.0, box=None, alternatives=None):
        self.text = text
        self.confidence = confidence
        self.box = box  # (x, y, w, h)
        self.alternatives = alternatives or []


def cleaned(text, new):
    t = normalize(text).strip()
    return repaired(t) if new else t


def rows_from(lines, new):
    usable = []
    for line in lines:
        if isinstance(line, str):
            line = {'text': line}
        text = cleaned(line['text'], new)
        if not text:
            continue
        box = (line['x'], line['y'], line['w'], line['h']) if 'y' in line else None
        alts = [cleaned(a, new) for a in line.get('alt', [])] if new else []
        alts = [a for a in alts if a][:3]
        usable.append((text, line.get('c', 1.0), box, alts))
    if not usable or any(u[2] is None for u in usable):
        return [Row(t, c, b, [a for a in alts if a != t]) for t, c, b, alts in usable]

    def mid(b):
        return b[1] + b[3] / 2
    srt = [u for _, u in sorted(enumerate(usable), key=lambda e: (mid(e[1][2]), e[1][2][0], e[0]))]
    groups = []
    for u in srt:
        b = u[2]
        if groups:
            ref = groups[-1][0][2]
            if abs(mid(b) - mid(ref)) <= 0.5 * min(b[3], ref[3]):
                groups[-1].append(u)
                continue
        groups.append([u])
    out = []
    for g in groups:
        g = sorted(g, key=lambda u: u[2][0])
        minx = min(u[2][0] for u in g)
        miny = min(u[2][1] for u in g)
        maxx = max(u[2][0] + u[2][2] for u in g)
        maxy = max(u[2][1] + u[2][3] for u in g)
        alternatives = []
        for i, seg in enumerate(g):
            for alt in seg[3]:
                if alt == seg[0]:
                    continue
                texts = [s[0] for s in g]
                texts[i] = alt
                joined = ' '.join(texts)
                if len(alternatives) < 3 and joined not in alternatives:
                    alternatives.append(joined)
        out.append(Row(' '.join(u[0] for u in g), min(u[1] for u in g), (minx, miny, maxx - minx, maxy - miny), alternatives))
    return out


# MARK: - 金額

def _valid_date(y, m, d):
    try:
        datetime.date(y, m, d)
        return True
    except ValueError:
        return False


def dates(t):
    r = []
    for m in re.finditer(r'(\d{4})\s*[年/.\-]\s*(\d{1,2})\s*[月/.\-]\s*(\d{1,2})\s*日?', t):
        if _valid_date(int(m[1]), int(m[2]), int(m[3])):
            r.append(m)
    for m in re.finditer(r'(令和|平成|R|H)\s*(\d{1,2}|元)\s*[年.]\s*(\d{1,2})\s*[月.]\s*(\d{1,2})\s*日?', t):
        ey = 1 if m[2] == '元' else int(m[2])
        base = 2018 if m[1] in ('令和', 'R') else 1988
        if ey > 0 and _valid_date(base + ey, int(m[3]), int(m[4])):
            r.append(m)
    return r


IGNORED = [r'\d{4}\s*[年/.\-]\s*\d{1,2}\s*[月/.\-]\s*\d{1,2}\s*日?',
           r'(令和|平成|R|H)\s*(\d{1,2}|元)\s*[年.]\s*\d{1,2}\s*[月.]\s*\d{1,2}\s*日?',
           r'\d{1,2}:\d{2}(:\d{2})?', r'\d{1,2}時\d{1,2}分', r'\(?0\d{1,4}\)?[\-\s]?\d{1,4}[\-\s]\d{3,4}',
           r'〒?\s*\d{3}-\d{4}', r'(\d{4}[\s\-*]){3}\d{1,4}', r'[*X]{2,}[\s\-*X]*\d{2,4}', r'T\d{13}']


def amounts(text):
    c = text
    for p in IGNORED:
        c = re.sub(p, ' ', c, flags=re.I)
    c = re.sub(r'(\d)-(?=\s|$)', r'\1', c)
    res = []
    for m in re.finditer(r'¥?\s*(\d{1,3}(?:,\d{3})+|\d+)(?!,\d)\s*(?:円)?', c):
        d = m.group(1).replace(',', '')
        if len(d) > 9:
            continue
        v = int(d)
        if not (1 <= v <= MAX_AMOUNT):
            continue
        before = c[m.start(1) - 1] if m.start(1) > 0 else ''
        after = c[m.end()] if m.end() < len(c) else ''
        if before and before in '0123456789,-/:.#*':
            continue
        if after and after in '0123456789,-/:.%点個件枚#*':
            continue
        res.append(v)
    return res


def is_amount_only(t):
    s = re.sub(r'[¥円,\s]', '', t)
    return s != '' and all(ch.isnumeric() for ch in s)


STRONG = ["総合計", "合計金額", "税込合計", "お買上金額", "お買上げ金額", "お買い上げ金額", "お買上計", "お買上げ計",
          "お支払額", "お支払金額", "お支払い金額", "お支払合計", "お支払い合計", "ご請求額", "ご請求金額", "請求額", "請求金額",
          "領収金額", "TOTAL AMOUNT", "GRAND TOTAL", "AMOUNT DUE"]
NOT_TOTAL = ["小計", "SUBTOTAL", "SUB TOTAL", "SUB-TOTAL", "消費税", "内税", "外税", "税額", "税率", "対象", "TAX",
             "お預り", "お預かり", "預り", "預かり", "お釣", "おつり", "釣銭", "つり銭", "CHANGE", "CASH", "現金",
             "値引", "割引", "DISCOUNT", "クーポン", "点数", "個数", "ITEM", "QTY", "ポイント", "POINT",
             "電話", "TEL", "番号", "NO.", "会員", "カード", "CARD"]
SUBTOTAL = ["小計", "SUBTOTAL", "SUB TOTAL", "SUB-TOTAL"]
WEIGHT = {'strong': 100, 'total': 50, 'sub': 0, 'calc': -10}
KIND_RANK = {'calc': -1, 'sub': 0, 'total': 1, 'strong': 2}


def totals(new):
    return ["合計", "お会計", "TOTAL"] + (["現計"] if new else [])


def contains_any(upper, words):
    return any(w.upper() in upper for w in words)


def matched_label(upper, labels):
    for label in sorted(labels, key=lambda x: -len(x)):
        if label.upper() in upper:
            return label
    return None


def amount_after(label, text):
    upper = text.upper()
    idx = upper.find(label.upper())
    if idx < 0:
        return None, False
    a = amounts(text[idx + len(label):])
    return (a[-1] if a else None), True


def is_short_note(text, new):
    return len(text) <= 8 and not re.search(r'[0-9]', text) and matched_label(text.upper(), STRONG + totals(new) + SUBTOTAL) is None


def amount_below(rows, i, new):
    index = i + 1
    if index >= len(rows):
        return None
    if new and is_short_note(rows[index].text, new) and index + 1 < len(rows):
        index += 1
    nxt = rows[index]
    nu = nxt.text.upper()
    if contains_any(nu, NOT_TOTAL) or matched_label(nu, STRONG + totals(new) + SUBTOTAL) is not None:
        return None
    if new and index + 1 < len(rows) and re.fullmatch(r'¥?\s*\d{1,3},?', nxt.text) \
            and re.fullmatch(r'\d{3}(,\d{3})*\s*円?', rows[index + 1].text):
        joined = (nxt.text + rows[index + 1].text).replace(' ', '')
        a = amounts(joined)
        if a:
            return a[-1], nxt
    if not is_amount_only(nxt.text):
        return None
    a = amounts(nxt.text)
    return (a[-1], nxt) if a else None


class Evidence:
    def __init__(self):
        self.subtotal = None
        self.outer_tax = 0
        self.discount = 0
        self.deposit = None
        self.change = None
        self.points = 0
        self.items_total = None

    @staticmethod
    def _unique(values):
        out = []
        for v in values:
            if 0 < v <= MAX_AMOUNT and v not in out:
                out.append(v)
        return out

    def subtotal_values(self):
        if self.subtotal is None:
            return []
        return self._unique([self.subtotal + self.outer_tax, self.subtotal + self.outer_tax - self.discount])

    def payment_values(self):
        if self.deposit is None or self.change is None or self.deposit < self.change:
            return []
        return self._unique([self.deposit - self.change, self.deposit - self.change + self.points])

    def item_values(self):
        if self.items_total is None:
            return []
        t = self.items_total
        return self._unique([t, t + self.outer_tax, t - self.discount, t + self.outer_tax - self.discount])

    def strong_values(self):
        return self._unique(self.subtotal_values() + self.payment_values())

    def supports(self, v):
        return v in self.subtotal_values() or v in self.payment_values() or v in self.item_values()

    def agreed(self):
        groups = [set(g) for g in (self.subtotal_values(), self.payment_values(), self.item_values()) if g]
        counts = {}
        for g in groups:
            for v in g:
                counts[v] = counts.get(v, 0) + 1
        agreed = [v for v, n in counts.items() if n >= 2]
        return agreed[0] if len(agreed) == 1 else None


def is_outer_tax_row(upper):
    if contains_any(upper, ["内", "対象", "INCL"]):
        return False
    return contains_any(upper, ["外税", "消費税", "TAX"]) and not contains_any(upper, ["小計", "SUBTOTAL", "SUB TOTAL"])


def totals_evidence(rows, new):
    e = Evidence()
    for i, row in enumerate(rows):
        up = row.text.upper()
        sub = matched_label(up, SUBTOTAL)
        if sub:
            others = [w for w in NOT_TOTAL if w not in SUBTOTAL]
            if not contains_any(up.replace(sub.upper(), ' '), others):
                v, _ = amount_after(sub, row.text)
                if v is None:
                    below = amount_below(rows, i, new)
                    v = below[0] if below else None
                if v is not None:
                    e.subtotal = v
            continue
        if is_outer_tax_row(up):
            a = amounts(row.text)
            if a:
                e.outer_tax += a[-1]
                continue
        if contains_any(up, ["値引", "割引", "DISCOUNT", "クーポン"]) and not contains_any(up, ["対象"]):
            d = discount_amount(row.text)
            if d is not None:
                e.discount += d
                continue
        if contains_any(up, ["ポイント", "POINT"]) and contains_any(up, ["利用", "使用", "支払"]):
            a = amounts(row.text)
            if a:
                e.points += a[-1]
                continue
        if contains_any(up, ["お預", "預り", "預かり"]):
            a = amounts(row.text)
            if a:
                e.deposit = a[-1]
                continue
        if contains_any(up, ["お釣", "おつり", "釣銭", "つり銭", "CHANGE"]):
            a = amounts(row.text)
            if a:
                e.change = a[-1]
            elif re.search(r'(^|[\s¥])0\s*円?$', row.text):
                e.change = 0
    items = line_items(rows, new)
    if items and all(it['amount'] is not None for it in items):
        e.items_total = sum(it['amount'] for it in items)
    return e


def labeled_candidates(rows, evidence, new):
    found = []
    last = max(len(rows) - 1, 1)
    for i, row in enumerate(rows):
        up = row.text.upper()
        sub = matched_label(up, SUBTOTAL)
        if sub:
            others = [w for w in NOT_TOTAL if w not in SUBTOTAL]
            if contains_any(up.replace(sub.upper(), ' '), others):
                continue
            kind, label, matched = 'sub', '小計', sub
        elif contains_any(up, NOT_TOTAL):
            continue
        elif matched_label(up, STRONG):
            kind = 'strong'
            label = matched = matched_label(up, STRONG)
        elif matched_label(up, totals(new)):
            kind = 'total'
            label = matched = matched_label(up, totals(new))
        else:
            continue
        found_amount, _ = amount_after(matched, row.text)
        source = row
        same = True
        if found_amount is None:
            below = amount_below(rows, i, new)
            if below:
                found_amount, source = below
                same = False
        if new:
            alternatives = [v for v in (amount_after(matched, a)[0] for a in row.alternatives) if v is not None]
            if not same:
                alternatives += [amounts(a)[-1] for a in source.alternatives if amounts(a)]
            if found_amount is None:
                found_amount = alternatives[0] if alternatives else None
            elif not evidence.supports(found_amount):
                better = next((a for a in alternatives if evidence.supports(a)), None)
                if better is not None:
                    found_amount = better
        if found_amount is None:
            continue
        pos = (row.box[1] + row.box[3] / 2) if row.box else i / last
        conf = min(row.confidence, source.confidence)
        consistent = new and evidence.supports(found_amount)
        score = WEIGHT[kind] + pos * 10 + conf * 3 + (2 if same else 1) + (20 if consistent else 0)
        found.append({'amount': found_amount, 'label': label, 'kind': kind, 'score': score, 'consistent': consistent})
    res = []
    for _, c in sorted(enumerate(found), key=lambda e: (-e[1]['score'], e[0])):
        if not any(r['amount'] == c['amount'] and r['label'] == c['label'] for r in res):
            res.append(c)
    return res


def selected_amount(cands):
    rec = [c for c in cands if c['kind'] in ('total', 'strong')]
    if not rec:
        return None, 'notFound'
    top = max(KIND_RANK[c['kind']] for c in rec)
    vals = {c['amount'] for c in rec if KIND_RANK[c['kind']] == top}
    if len(vals) != 1:
        return None, 'ambiguous'
    return vals.pop(), None


def amount_analysis(rows, new):
    evidence = totals_evidence(rows, new) if new else Evidence()
    cands = labeled_candidates(rows, evidence, new)
    amount, issue = selected_amount(cands)
    warning = False
    if new:
        if amount is not None and not evidence.supports(amount):
            agreed = evidence.agreed()
            if agreed is not None and agreed != amount:
                amount, issue = None, 'inconsistent'
            elif evidence.strong_values():
                warning = True
        agreed = evidence.agreed()
        if amount is None and agreed is not None and not any(c['amount'] == agreed for c in cands):
            cands.append({'amount': agreed, 'label': '計算', 'kind': 'calc', 'score': 0, 'consistent': True})
    return {'candidates': cands, 'amount': amount, 'issue': None if amount is not None else (issue or 'notFound'),
            'warning': warning and amount is not None}


# MARK: - 商品明細

ITEMS_END = ["小計", "SUBTOTAL", "SUB TOTAL", "合計", "お会計", "TOTAL", "総合計", "お買上", "お買い上", "お支払", "ご請求", "請求額", "領収金額",
             "お預", "預り", "預かり", "お釣", "おつり", "釣銭", "つり銭", "支払", "現金", "CASH", "CHANGE", "クレジット", "電子マネー", "AMOUNT DUE"]
NOT_ITEM = ["消費税", "内税", "外税", "税率", "税額", "対象", "TAX", "値引", "割引", "DISCOUNT", "クーポン",
            "ポイント", "POINT", "カード", "CARD", "会員", "TEL", "電話", "FAX", "〒", "住所", "登録", "インボイス",
            "レジ", "担当", "責任者", "NO.", "番号", "伝票", "取引", "領収", "レシート", "RECEIPT", "明細",
            "WWW", "HTTP", ".COM", ".JP", "ありがとう", "いらっしゃいませ", "ご来店", "またのお越し", "営業時間",
            "点数", "個数", "買上点", "ITEM", "QTY"]


def number(text, mx):
    c = re.sub(r'[¥円,点個\s]', '', normalize(text))
    if not c or len(c) > 9 or not all('0' <= ch <= '9' for ch in c):
        return None
    v = int(c)
    return v if 1 <= v <= mx else None


def is_letter(ch):
    import unicodedata
    cat = unicodedata.category(ch)
    return cat.startswith('L') or cat.startswith('M')


def _first(pattern, text):
    m = re.search(pattern, text, re.I)
    if not m:
        return None
    return [g or '' for g in m.groups()], text[:m.start()] + ' ' + text[m.end():]


NUM = r'(¥?\s*\d{1,3}(?:,\d{3})+\s*円?|¥?\s*\d+\s*円?)'


def parse_item(text):
    if contains_any(text.upper(), NOT_ITEM) or dates(text) or re.search(r'\d{1,2}:\d{2}', text) \
            or re.search(r'(丁目|番地|(都|道|府|県).{0,6}(市|区|郡|町|村))', text):
        return None
    rest, q, u = text, None, None
    m = _first(NUM + r'\s*(?:点|個|コ)?\s*[x×X＊]\s*' + NUM, rest)
    if m:
        left, right = m[0]
        lv, rv = number(left, MAX_AMOUNT), number(right, MAX_AMOUNT)
        lm = '¥' in left or '円' in left
        rm = '¥' in right or '円' in right
        if lm and not rm:
            u, q = lv, (rv if rv is not None and rv <= 999 else None)
        elif rm and not lm:
            q, u = (lv if lv is not None and lv <= 999 else None), rv
        elif lv is not None and lv <= 99:
            q, u = lv, rv
        elif rv is not None and rv <= 99:
            u, q = lv, rv
        if q is not None or u is not None:
            rest = m[1]
    if u is None:
        m = _first(r'(?:@|単価|単)\s*' + NUM, rest)
        if m:
            u = number(m[0][0], MAX_AMOUNT)
            rest = m[1]
    if q is None:
        m = _first(r'(?<![\d,])(\d{1,3})\s*(?:点|個|コ)(?![入切])', rest)
        if m:
            q = int(m[0][0])
            rest = m[1]
    a = None
    m = _first(r'(?:^|\s|(?=¥))(¥?\s*\d{1,3}(?:,\d{3})+|¥?\s*\d+)\s*円?-?\s*[※*★軽外内非]*\s*$', rest)
    if m:
        v = amounts(m[0][0])
        if v:
            a = v[-1]
            rest = m[1]
    name = re.sub(r'^\s*\d{4,}\s+', '', rest).strip('※*★・-_=|:：@× \t')
    if sum(1 for ch in name if is_letter(ch)) == 0:
        if q is None and u is None and a is None:
            return None
        return ('', q, u, a)
    return (name[:40], q, u, a)


def best_parse(row, new):
    main = parse_item(row.text)
    if main is None or not new:
        return main
    name, q, u, a = main
    needs = (q * u != a) if (q is not None and u is not None and a is not None) else (a is None)
    if not needs:
        return main
    for alt in row.alternatives:
        p = parse_item(alt)
        if p is None:
            continue
        fits = p[1] is not None and p[2] is not None and p[3] is not None and p[1] * p[2] == p[3]
        if fits or (a is None and p[3] is not None and p[1] == q and p[2] == u):
            return (name, p[1], p[2], p[3])
    return main


def line_items(rows, new):
    end_words = ITEMS_END + (["現計"] if new else [])
    start, end = 0, len(rows)
    for i, r in enumerate(rows):
        if contains_any(r.text.upper(), end_words):
            end = i
            break
    for i in range(end):
        if dates(rows[i].text) or re.search(r'\d{1,2}:\d{2}', rows[i].text):
            start = i + 1
    if start >= end:
        return []
    items = []
    for r in rows[start:end]:
        p = best_parse(r, new)
        if p is None:
            continue
        if p[0] == '':
            if not items:
                continue
            last = items.pop()
            for key, v in (('quantity', p[1]), ('unitPrice', p[2]), ('amount', p[3])):
                if last[key] is None and v is not None:
                    last[key] = v
            items.append(last)
        else:
            items.append({'name': p[0], 'quantity': p[1], 'unitPrice': p[2], 'amount': p[3]})
    return [it for it in items if it['amount'] is not None or it['unitPrice'] is not None][:50]


def extract(lines, new):
    rows = rows_from(lines, new)
    analysis = amount_analysis(rows, new)
    return {'amount': analysis['amount'], 'issue': analysis['issue'], 'warning': analysis['warning'],
            'candidates': [(c['amount'], c['label'], c['kind']) for c in analysis['candidates'][:5]],
            'items': line_items(rows, new)}


# MARK: - 比べる

def items_match(actual, expected):
    if expected is None:
        return True
    simplified = [[it['name'], it['quantity'], it['unitPrice'], it['amount']] for it in actual]
    return simplified == expected


def main(path):
    with open(path, encoding='utf-8') as handle:
        fixtures = json.load(handle)['receipts']
    totals_ok = {'old': 0, 'new': 0}
    items_ok = {'old': 0, 'new': 0}
    wrong_auto = {'old': 0, 'new': 0}
    print(f'{"ID":32} {"種類":14} {"期待":>8} {"Build 21":>16} {"Build 22":>16}')
    for fixture in fixtures:
        expected = fixture['expected']
        row = []
        for version, new in (('old', False), ('new', True)):
            result = extract(fixture['lines'], new)
            ok = (result['amount'] == expected['amount']
                  and (expected.get('issue') is None or result['issue'] == expected['issue'])
                  and (not new or result['warning'] == bool(expected.get('warning'))))
            if ok:
                totals_ok[version] += 1
            if result['amount'] is not None and result['amount'] != expected['amount']:
                wrong_auto[version] += 1
            if items_match(result['items'], expected.get('items')):
                items_ok[version] += 1
            shown = '空' if result['amount'] is None else str(result['amount'])
            row.append(f'{shown}{"" if ok else " ✗"}')
        want = '空' if expected['amount'] is None else str(expected['amount'])
        print(f'{fixture["id"]:32} {fixture["kind"]:14} {want:>8} {row[0]:>16} {row[1]:>16}')
    n = len(fixtures)
    print()
    print(f'合計金額が期待どおり：Build 21 {totals_ok["old"]}/{n}、Build 22 {totals_ok["new"]}/{n}')
    print(f'商品明細が期待どおり：Build 21 {items_ok["old"]}/{n}、Build 22 {items_ok["new"]}/{n}')
    print(f'間違った金額を自動で入れた：Build 21 {wrong_auto["old"]}件、Build 22 {wrong_auto["new"]}件')
    return 0 if totals_ok['new'] == n and items_ok['new'] == n and wrong_auto['new'] == 0 else 1


if __name__ == '__main__':
    default = os.path.join(os.path.dirname(__file__), '..', '..', 'LifeOSTests', 'Fixtures', 'JapaneseSyntheticReceipts.json')
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else default))
