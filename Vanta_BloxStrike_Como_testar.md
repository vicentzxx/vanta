# VANTA BloxStrike — teste 0.7

Arquivo: `Vanta_BloxStrike_Teste.lua`. Esta adaptação aceita os places do universo `7633926880` da [experiência BloxStrike](https://www.roblox.com/games/114234929420007/BloxStrike).

## Correções desta versão

- ESP somente com o **corpo atual**, projetado novamente a cada quadro. Cabeça, raiz e pés disponíveis ajustam a caixa enquanto o personagem anda, agacha ou pula. Não conserva coordenadas de um quadro anterior para desenhar uma caixa parada.
- Corrige a rejeição de alvos pelo erro **consulta da camera falhou**, confirmado no diagnóstico da v0.5 no Xeno. A consulta extra da câmera foi removida; a checagem de paredes usa o percurso por raio.
- Peças auxiliares invisíveis e sem colisão podem ser ignoradas durante esse teste, com limite de tentativas. Paredes visíveis, vidro e barreiras com colisão continuam bloqueando. Falhas da consulta por raio continuam tornando o alvo inelegível.
- Reconhece o contêiner **ReplicatedStorage._PVS_CulledCharacters** observado no diagnóstico real. Um modelo ali não é usado como alvo de mira nem como posição atual do ESP.
- A memória de **última posição** da v0.6 foi removida. Se o jogo ocultar ou remover o corpo, a caixa desaparece na atualização seguinte. Quando o corpo retorna ao Workspace, a caixa usa sua nova posição.
- O status informa **Ocultos pelo jogo**, para distinguir corpos indisponíveis de um filtro de distância.
- Novo controle **ESP: N studs**, abaixo da força da mira, com botões **− / +**. Ajusta de **250 a 10000 studs**, em passos de **250**, começando em **2500**. A mudança vale na atualização seguinte das caixas e não altera o alcance da mira. Se precisar, role o painel para alcançar o controle no celular.
- Modelos fora do Workspace e partes removidas deixam de ser aceitos para mira e ESP. Ter apenas um Parent não confirma que o corpo continua no mundo ativo. A validação usa a hierarquia de [Instance](https://create.roblox.com/docs/reference/engine/classes/Instance#IsDescendantOf).
- Caixa e mira usam a mesma referência do corpo. Uma raiz ou um pé distante dessa referência não desloca a caixa para outro ponto.
- As caixas são escondidas antes de cada atualização e redesenhadas usando as posições atuais disponíveis. Uma falha individual não interrompe os demais jogadores ou a seleção de outros alvos.
- Descoberta de partes, equipes, vida e atributos é reutilizada apenas dentro do mesmo quadro. No quadro seguinte a observação recomeça. Não há prazo de expiração por falta de movimento: um jogador parado pode continuar válido.
- Com **Checar paredes: ON**, a mira testa o trajeto completo até o alvo, ignorando o próprio modelo do alvo durante o teste. Isso evita aceitar um hitbox que intercepte o raio antes da parede. Obstáculos detectados ou falhas da consulta por raio tornam o alvo inelegível.
- O ESP permanece independente desse filtro de mira: um corpo detectado atrás de um obstáculo ainda pode receber caixa. **Vermelho** indica percurso considerado livre; **amarelo [parede]** indica obstáculo detectado; **amarelo [?]** indica consulta inconclusiva. Isso descreve o resultado das consultas locais, sem garantir a visibilidade real do adversário.
- O botão **Copiar diagnostico**, abaixo do status no painel, registra sua equipe detectada, vida local, modo de entrada, modelo e parte escolhidos, posição, motivo de rejeição do alvo e obstáculo encontrado. Também lista modelos com partes de corpo no contêiner Characters que não foram associados a um Player; eles podem incluir NPCs. Copia para a área de transferência se o executor oferecer essa função; caso contrário, imprime no console. O relatório não é enviado automaticamente.

## Como testar

1. Execute o carregador abaixo e confirme o título **VANTA | BLOX v0.7**. A instância anterior do VANTA é encerrada durante a troca.
2. Ative **ESP inimigos** e mantenha **Checar paredes: ON**.
3. Confira **Minha equipe**. Se Auto não identificar seu lado, selecione **CT** ou **T**. A escolha informa apenas o seu lado ao filtro; aliados, espectadores identificados e equipes desconhecidas continuam excluídos.
4. Ative **Mira** com **Entrada: Camera**. A força começa em 100% e pode ser reduzida pelos botões. O modo Mouse depende do executor e exige o mouse travado pelo jogo.
5. Observe um adversário andando, parando e passando atrás de uma parede. A caixa deve acompanhar o corpo disponível no cliente. Se o obstáculo for detectado, a caixa muda para amarelo e a mira deixa de selecionar aquele alvo enquanto a checagem estiver ligada.
   Confira também a caixa enquanto o adversário agacha e pula. Se o jogo mover o corpo para o contêiner PVS, a caixa desaparece imediatamente. O contador de ocultos ajuda a distinguir esse caso de um limite de distância.
6. Para aumentar o alcance do ESP, use **+** ao lado de **ESP: N studs** e teste **5000** ou **10000**. O regulador altera apenas o filtro de distância; se o jogo não fornecer o corpo distante ao cliente, aumentar o número não cria essa informação.
7. Se surgir uma caixa sem ninguém naquele ponto ou faltar a de um adversário mesmo dentro do alcance selecionado, clique em **Copiar diagnostico durante a falha** e cole o relatório no chat. O relatório inclui os alcances de ESP e mira. No PC, o console pode ser aberto com F9 se a cópia não estiver disponível.

O ESP usa caixas 2D na região visível da tela e o alcance escolhido no regulador. O alcance da mira continua em 2500 studs. Não inclui setas para alvos atrás da câmera. Continua trabalhando com corpos associados a objetos Player; NPCs separados, inclusive os de Zombies, ainda não foram adaptados. O diagnóstico não prova se um Player é controlado por uma pessoa ou um bot. Mira, ESP e Anti-Kick local começam desligados. O botão **X** encerra os recursos e remove a interface.

## Limites e validação

A sintaxe e **77 testes locais em simulação** passaram. Incluem o erro da consulta extra da câmera, peças auxiliares, barreiras reais, filtros CT/T, vida, modelos alternativos, partes aninhadas, troca de personagem/equipe, remoção de modelos, coerência das caixas, deslocamento ao andar/agachar/pular, isolamento de um corpo inválido, ocultação PVS e retomada da posição atual. O diagnóstico real confirmou a falha da v0.5; a aparência e a resposta da v0.7 ainda precisam ser confirmadas em uma partida.

Um modelo que permanece no Workspace pode estar desatualizado por uma regra específica do jogo. A ausência de movimento sozinha não permite diferenciá-lo de um adversário parado. A vida desconhecida também não confirma se um corpo está vivo; isso aparece no diagnóstico.

O diagnóstico recebido mostrou **StreamingEnabled=false**, mas também mostrou a ocultação PVS feita pelo próprio jogo. Portanto, aumentar o alcance não resolve sozinho esse caso. Isso é distinto do [streaming do Roblox](https://create.roblox.com/docs/workspace/streaming). A v0.7 não altera o sistema de ocultação do jogo nem move os modelos de volta ao Workspace. Sem um corpo atual disponível, remove a caixa. As consultas de [raycasting](https://create.roblox.com/docs/workspace/raycasting) também dependem da geometria disponível no cliente.

O Anti-Kick opcional filtra determinadas chamadas locais e não impede expulsões do servidor ou banimentos.

## Carregador

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/vicentzxx/vanta/refs/heads/main/Vanta_BloxStrike_Teste.lua?v=0.7"))()
```
