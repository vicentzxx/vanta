# VANTA BloxStrike — teste 0.5

Arquivo: `Vanta_BloxStrike_Teste.lua`. Esta adaptação aceita os places do universo `7633926880` da [experiência BloxStrike](https://www.roblox.com/games/114234929420007/BloxStrike).

## Correções desta versão

- Novo controle **ESP: N studs**, abaixo da força da mira, com botões **− / +**. Ajusta de **250 a 10000 studs**, em passos de **250**, começando em **2500**. A mudança vale na atualização seguinte das caixas e não altera o alcance da mira. Se precisar, role o painel para alcançar o controle no celular.
- Modelos fora do Workspace e partes removidas deixam de ser aceitos para mira e ESP. Ter apenas um Parent não confirma que o corpo continua no mundo ativo. A validação usa a hierarquia de [Instance](https://create.roblox.com/docs/reference/engine/classes/Instance#IsDescendantOf).
- Caixa e mira usam a mesma referência do corpo. Uma raiz ou um pé distante dessa referência não desloca a caixa para outro ponto.
- As caixas são escondidas antes de cada atualização e redesenhadas usando as posições atuais. Um corpo inválido não conserva a caixa no último lugar; uma falha individual também não interrompe os demais jogadores.
- Descoberta de partes, equipes, vida e atributos é reutilizada apenas dentro do mesmo quadro. No quadro seguinte a observação recomeça. Não há prazo de expiração por falta de movimento: um jogador parado pode continuar válido.
- Com **Checar paredes: ON**, a mira testa o trajeto completo até o alvo, ignorando o próprio modelo do alvo durante o teste. Isso evita aceitar um hitbox que intercepte o raio antes da parede. Há também uma consulta complementar da câmera. Obstáculos detectados ou falhas nessas consultas tornam o alvo inelegível.
- O ESP permanece independente desse filtro de mira: um corpo detectado atrás de um obstáculo ainda pode receber caixa. **Vermelho** indica percurso considerado livre; **amarelo [parede]** indica obstáculo detectado; **amarelo [?]** indica consulta inconclusiva. Isso descreve o resultado das consultas locais, sem garantir a visibilidade real do adversário.
- O botão **Copiar diagnostico**, abaixo do status no painel, registra o modelo e a parte escolhidos, posição, equipe, vida conhecida e resultado da consulta de obstáculos. Copia para a área de transferência se o executor oferecer essa função; caso contrário, imprime no console. O relatório não é enviado automaticamente.

## Como testar

1. Execute o carregador abaixo e confirme o título **VANTA | BLOX v0.5**. A instância anterior do VANTA é encerrada durante a troca.
2. Ative **ESP inimigos** e mantenha **Checar paredes: ON**.
3. Confira **Minha equipe**. Se Auto não identificar seu lado, selecione **CT** ou **T**. A escolha informa apenas o seu lado ao filtro; aliados, espectadores identificados e equipes desconhecidas continuam excluídos.
4. Ative **Mira** com **Entrada: Camera**. A força começa em 100% e pode ser reduzida pelos botões. O modo Mouse depende do executor e exige o mouse travado pelo jogo.
5. Observe um adversário andando, parando e passando atrás de uma parede. A caixa deve acompanhar o corpo disponível no cliente. Se o obstáculo for detectado, a caixa muda para amarelo e a mira deixa de selecionar aquele alvo enquanto a checagem estiver ligada.
6. Para aumentar o alcance do ESP, use **+** ao lado de **ESP: N studs** e teste **5000** ou **10000**. O regulador altera apenas o filtro de distância; se o jogo não fornecer o corpo distante ao cliente, aumentar o número não cria essa informação.
7. Se surgir uma caixa sem ninguém naquele ponto ou faltar a de um adversário mesmo dentro do alcance selecionado, clique em **Copiar diagnostico durante a falha** e cole o relatório no chat. O relatório inclui os alcances de ESP e mira. No PC, o console pode ser aberto com F9 se a cópia não estiver disponível.

O ESP usa caixas 2D na região visível da tela e o alcance escolhido no regulador. O alcance da mira continua em 2500 studs. Não inclui setas para alvos atrás da câmera nem NPCs do modo Zombies. Mira, ESP e Anti-Kick local começam desligados. O botão **X** encerra os recursos e remove a interface.

## Limites e validação

A sintaxe e **66 testes locais em simulação** passaram. Incluem filtros CT/T, vida, modelos alternativos, partes aninhadas, troca de personagem/equipe, remoção de modelos, coerência das caixas, posições móveis, paredes, falhas de consulta e isolamento de um corpo inválido. A aparência e o comportamento desta versão ainda precisam ser confirmados em uma partida real.

Um modelo que permanece no Workspace pode estar desatualizado por uma regra específica do jogo. A ausência de movimento sozinha não permite diferenciá-lo de um adversário parado. A vida desconhecida também não confirma se um corpo está vivo; isso aparece no diagnóstico.

O cliente pode deixar de receber partes devido a [streaming](https://create.roblox.com/docs/workspace/streaming) ou regras do jogo. Sem um corpo e uma posição disponíveis, esta versão remove a marcação em vez de apresentar a última posição como atual. As consultas de [raycasting](https://create.roblox.com/docs/workspace/raycasting) também dependem da geometria disponível no cliente.

O Anti-Kick opcional filtra determinadas chamadas locais e não impede expulsões do servidor ou banimentos.

## Carregador

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/vicentzxx/vanta/main/Vanta_BloxStrike_Teste.lua?v=0.5"))()
```
