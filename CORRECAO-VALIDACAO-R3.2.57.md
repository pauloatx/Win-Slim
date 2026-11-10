# R3.2.57 — correção do validador

O teste de recusa de HW-GPU-IRQ-AFFINITY encerrava prematuramente no Windows PowerShell 5.1 por converter stderr nativo em erro terminante. Agora captura a saída com política temporária Continue, restaura a política em finally e exige código 1 e a mensagem específica. Outros erros continuam reprovando. Corrigidos dois rótulos que mencionavam HAGS em um teste do overlay CS2.

Nenhuma alteração na interface, motor, contratos GPU, permissões ou backups. O bloqueio de afinidade permanece. O manifesto foi atualizado somente para o teste corrigido.

Extraia esta pasta separadamente e execute Validar-GPU-R3.2.57.bat nas duas máquinas. Envie logs/gate-native-r3.2.57.log. O teste não aplica otimizações reais. A correção ainda precisa desta confirmação no Windows PowerShell 5.1.
