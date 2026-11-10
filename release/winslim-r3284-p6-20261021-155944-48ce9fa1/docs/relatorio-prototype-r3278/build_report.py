#!/usr/bin/env python3
"""Win-Slim R3.2.78: relatório de outcome, sem modificar o journal original."""
import json, sys, html
from pathlib import Path
from collections import OrderedDict, Counter

STATUS = {'AppliedVerified': ('Aplicado e verificado', 'ok'), 'AlreadyConfigured': ('Já configurado', 'same'), 'Failed': ('Falhou', 'bad'), 'Skipped': ('Ignorado', 'skip'), 'Excluded': ('Excluído', 'skip')}

def render(data):
    items = data.get('items') or []
    groups = OrderedDict()
    for item in items:
        key = (str(item.get('Id','—')), str(item.get('Name','—')))
        groups.setdefault(key, []).append(item)
    for item in data.get('excluded') or []:
        key = (str(item.get('Id','—')), str(item.get('Name','—')))
        groups.setdefault(key, []).append(dict(item, Status='Excluded'))
    def esc(v): return html.escape(str(v), quote=True)
    rows = []
    for (tid,name), entries in groups.items():
        counts = Counter(str(e.get('Status','Unknown')) for e in entries)
        summ = ', '.join(f'{STATUS.get(s,(s,"skip"))[0]}: {n}' for s,n in counts.items())
        details = ''.join('<li>'+esc(STATUS.get(e.get('Status'), (e.get('Status','Desconhecido'),''))[0]) + (' — '+esc(e['Reason']) if e.get('Reason') else '')+'</li>' for e in entries)
        bad = any(s in counts for s in ('Failed','Error'))
        css = 'bad' if bad else ('ok' if 'AppliedVerified' in counts else ('skip' if 'Excluded' in counts else 'same'))
        rows.append(f'<tr><td><strong>{esc(tid)}</strong></td><td>{esc(name)}</td><td class="{css}">{esc(summ)}</td><td><details><summary>{len(entries)} valor(es)</summary><ul>{details}</ul></details></td></tr>')
    count_applied = sum(i.get('Status')=='AppliedVerified' for i in items)
    count_same = sum(i.get('Status')=='AlreadyConfigured' for i in items)
    discrepancy = (data.get('changed') is not None and data['changed'] != count_applied) or (data.get('unchanged') is not None and data['unchanged'] != count_same)
    verified = data.get('verified') is True
    status = 'Verificado' if verified and not data.get('errors') and not discrepancy else 'Requer revisão'
    warning = '<p class="bad">Atenção: os contadores do outcome não correspondem aos itens.</p>' if discrepancy else ''
    return f'''<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Win-Slim — Relatório de aplicação</title><style>body{{background:#08090b;color:#f1f1f1;font:15px Segoe UI,Arial,sans-serif;margin:0}}main{{max-width:1100px;margin:36px auto;padding:0 22px}}h1{{font-size:26px;margin-bottom:6px}}.sub{{color:#aeb7c1}}.cards{{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:12px;margin:26px 0}}.card{{background:#141719;border:1px solid #313943;padding:18px;border-radius:10px}}.num{{font-size:25px;color:#ff8400;font-weight:700}}table{{width:100%;border-collapse:collapse;background:#111416}}th,td{{padding:14px;border-bottom:1px solid #303840;text-align:left;vertical-align:top}}th{{color:#ff8a13}}.ok{{color:#6ddaa3}}.same{{color:#cdd6df}}.skip{{color:#f5c56b}}.bad{{color:#ff7d83}}details{{cursor:pointer}}li{{margin:8px 0}}footer{{margin:28px 0;color:#94a2af;font-size:13px}}@media(max-width:650px){{table{{font-size:12px}}th,td{{padding:8px}}}}</style></head><body><main><h1>Relatório de aplicação</h1><p class="sub">{esc(data.get('profile','Win-Slim Suite'))} · {esc(data.get('utc',''))}</p><div class="cards"><div class="card"><div>Status</div><div class="num">{esc(status)}</div></div><div class="card"><div>Valores aplicados</div><div class="num">{count_applied}</div></div><div class="card"><div>Já configurados</div><div class="num">{count_same}</div></div><div class="card"><div>Tweaks distintos</div><div class="num">{len(groups)}</div></div></div>{warning}<h2>Resumo por ajuste</h2><table><thead><tr><th>ID</th><th>Ajuste</th><th>Resultado</th><th>Detalhes</th></tr></thead><tbody>{''.join(rows)}</tbody></table><footer>Relatório somente leitura gerado a partir do outcome.json; não altera Registro, serviços ou backups. Verificação declarada pelo mecanismo original: {esc(verified)}. Backup: {esc(data.get('backupId','—'))}. Valores contados individualmente; tweaks agrupados por ID e nome.</footer></main></body></html>'''

def main():
    if len(sys.argv) != 3: raise SystemExit('Uso: python build_report.py outcome.json relatorio.html')
    source,target = map(Path,sys.argv[1:])
    obj=json.loads(source.read_text(encoding='utf-8-sig'))
    target.write_text(render(obj),encoding='utf-8')
    print(f'Relatório criado: {target}')
if __name__=='__main__':main()
