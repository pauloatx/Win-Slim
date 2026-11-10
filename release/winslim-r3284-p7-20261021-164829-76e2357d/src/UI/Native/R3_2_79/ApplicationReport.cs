using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Security;
using System.Text;

namespace WinSlim.NativeUI
{
    public sealed class ApplicationReportRow
    {
        public string Id, Name;
        public int Applied, Unchanged, Other;
        public readonly List<string> Details = new List<string>();
    }

    // Pure presentation: never opens journals, launches commands or writes backups/Registry.
    public sealed class ApplicationReport
    {
        public readonly List<ApplicationReportRow> Rows = new List<ApplicationReportRow>();
        public readonly List<string> Warnings = new List<string>();
        public int Applied, Unchanged, Values, Excluded;
        public bool Verified;
        public string Profile, Utc, BackupId, ReportPath;

        private static string Text(IDictionary<string, object> obj, string key)
        {
            object value;
            return obj != null && obj.TryGetValue(key, out value) && value != null ? Convert.ToString(value, CultureInfo.InvariantCulture) : "";
        }
        private static IEnumerable<object> Entries(IDictionary<string, object> obj, string key)
        {
            object value;
            if (obj == null || !obj.TryGetValue(key, out value) || value == null) yield break;
            IEnumerable list = value as IEnumerable;
            if (list == null || value is string || value is IDictionary) { yield return value; yield break; }
            foreach (object entry in list) yield return entry;
        }
        private static bool CountMatches(IDictionary<string, object> obj, string key, int expected)
        {
            int n;
            return Int32.TryParse(Text(obj, key), NumberStyles.Integer, CultureInfo.InvariantCulture, out n) && n >= 0 && n == expected;
        }
        public static string StatusLabel(string status)
        {
            switch (status) {
                case "AppliedVerified": return "Aplicado e verificado";
                case "AlreadyConfigured": return "Já configurado";
                case "RolledBack": return "Desfeito após falha";
                case "RecoveryIncomplete": return "Recuperação incompleta";
                case "NotApplied": return "Não aplicado";
                case "Failed": case "Error": return "Falhou";
                case "Skipped": return "Ignorado";
                case "Excluded": return "Excluído";
                default: return "Status desconhecido: " + status;
            }
        }
        public static ApplicationReport Create(IDictionary<string, object> source)
        {
            if (source == null) throw new ArgumentNullException("source");
            ApplicationReport report = new ApplicationReport();
            report.Profile = Text(source, "profile"); report.Utc = Text(source, "utc");
            report.BackupId = Text(source, "backupId"); report.ReportPath = Text(source, "reportPath");
            Dictionary<string, ApplicationReportRow> groups = new Dictionary<string, ApplicationReportRow>(StringComparer.OrdinalIgnoreCase);
            bool unsafeStatus = false;
            foreach (string section in new string[] { "items", "excluded" }) {
                foreach (object value in Entries(source, section)) {
                    IDictionary<string, object> entry = value as IDictionary<string, object>;
                    if (entry == null) { report.Warnings.Add("Entrada inválida no relatório."); continue; }
                    string id = Text(entry, "Id"), name = Text(entry, "Name");
                    if (String.IsNullOrWhiteSpace(id)) { report.Warnings.Add("Ajuste sem identificação."); continue; }
                    ApplicationReportRow row;
                    if (!groups.TryGetValue(id, out row)) {
                        row = new ApplicationReportRow { Id = id, Name = name }; groups.Add(id, row); report.Rows.Add(row);
                    }
                    if (section == "excluded") {
                        report.Excluded++;
                        row.Details.Add("Excluído — " + Text(entry, "Reason"));
                        continue;
                    }
                    report.Values++;
                    string status = Text(entry, "Status");
                    if (status == "AppliedVerified") { row.Applied++; report.Applied++; }
                    else if (status == "AlreadyConfigured") { row.Unchanged++; report.Unchanged++; }
                    else { row.Other++; unsafeStatus = true; }
                    row.Details.Add(StatusLabel(status));
                }
            }
            foreach (object error in Entries(source, "errors")) report.Warnings.Add(Convert.ToString(error, CultureInfo.InvariantCulture));
            if (!String.IsNullOrWhiteSpace(Text(source, "reportError"))) report.Warnings.Add(Text(source, "reportError"));
            if (!CountMatches(source, "changed", report.Applied) || !CountMatches(source, "unchanged", report.Unchanged))
                report.Warnings.Add("Os contadores do resultado não correspondem aos itens; confira o registro original.");
            object verified;
            report.Verified = source.TryGetValue("verified", out verified) && verified is bool && (bool)verified &&
                report.Values > 0 && !unsafeStatus && report.Warnings.Count == 0;
            return report;
        }
        public string ToText()
        {
            StringBuilder text = new StringBuilder();
            text.AppendLine(Verified ? "Aplicação verificada" : "Requer revisão");
            text.AppendLine(Profile);
            text.AppendLine(String.Format(CultureInfo.InvariantCulture, "{0} valores aplicados · {1} já configurados · {2} ajustes distintos · {3} excluídos.", Applied, Unchanged, Rows.Count, Excluded));
            text.AppendLine();
            foreach (ApplicationReportRow row in Rows) {
                text.AppendLine(row.Id + " — " + row.Name);
                text.AppendLine(String.Format(CultureInfo.InvariantCulture, "  {0} aplicados · {1} já configurados", row.Applied, row.Unchanged));
                if (row.Other > 0) text.AppendLine("  " + row.Other + " valores com outro resultado");
                foreach (string detail in row.Details) if (detail.StartsWith("Excluído", StringComparison.Ordinal) || row.Other > 0) text.AppendLine("  " + detail);
                text.AppendLine();
            }
            foreach (string warning in Warnings) text.AppendLine("Atenção: " + warning);
            text.AppendLine("Backup: " + BackupId);
            text.AppendLine("Data (UTC): " + Utc);
            text.AppendLine("Registro original: " + ReportPath);
            return text.ToString();
        }
        private static string Html(string value) { return SecurityElement.Escape(value ?? "") ?? ""; }
        public string ToHtml()
        {
            StringBuilder html = new StringBuilder("<!doctype html><html lang=\"pt-BR\"><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>Win-Slim — Relatório</title><style>body{background:#0b0d10;color:#eef0f3;font:15px 'Segoe UI',sans-serif;margin:24px}main{max-width:1080px;margin:auto}h1{color:#ff9500}table{border-collapse:collapse;width:100%}th,td{border:1px solid #596473;padding:12px;text-align:left;vertical-align:top}th{background:#20262e}p{line-height:1.6}.warning{color:#ffb5b5}details{cursor:pointer}@media(prefers-color-scheme:light){body{background:#f5f6f8;color:#152337}h1{color:#a94b00}th{background:#e5eaf0}.warning{color:#a31323}}@media(max-width:650px){body{margin:12px}th,td{padding:7px;font-size:12px}table{overflow-wrap:anywhere}}</style><main>");
            html.Append("<h1>").Append(Verified ? "Aplicação verificada" : "Requer revisão").Append("</h1><p>").Append(Html(Profile)).Append("</p><p>");
            html.Append(Applied).Append(" valores aplicados · ").Append(Unchanged).Append(" já configurados · ").Append(Rows.Count).Append(" ajustes distintos · ").Append(Excluded).Append(" excluídos</p>");
            foreach (string warning in Warnings) html.Append("<p class=\"warning\">").Append(Html(warning)).Append("</p>");
            html.Append("<table><thead><tr><th>ID</th><th>Ajuste</th><th>Aplicados / já configurados</th><th>Detalhes</th></tr></thead><tbody>");
            foreach (ApplicationReportRow row in Rows) {
                html.Append("<tr><td>").Append(Html(row.Id)).Append("</td><td>").Append(Html(row.Name)).Append("</td><td>").Append(row.Applied).Append(" / ").Append(row.Unchanged).Append("</td><td><details><summary>Ver resultados</summary><ul>");
                foreach (string detail in row.Details) html.Append("<li>").Append(Html(detail)).Append("</li>");
                html.Append("</ul></details></td></tr>");
            }
            html.Append("</tbody></table><p>Backup: ").Append(Html(BackupId)).Append("<br>Data (UTC): ").Append(Html(Utc)).Append("<br>Registro original: ").Append(Html(ReportPath)).Append("</p><p>Relatório de leitura. A verificação confirma os valores no Registro; confira o efeito nas configurações do Windows.</p></main></html>");
            return html.ToString();
        }
    }
}
