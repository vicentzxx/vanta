# VANTA BloxStrike — versão de teste 0.1

Arquivo: `Vanta_BloxStrike_Teste.lua`.

Esta adaptação usa o universo da [experiência BloxStrike](https://www.roblox.com/games/114234929420007/BloxStrike), identificado como `7633926880` pela API pública do Roblox. Ela aceita os places desse universo e interrompe a execução se estiver em outro jogo.

## O que mudou

- Painel identificado como BloxStrike, com rolagem para telas menores.
- Filtro de equipes por atributo `Team` do Player ou Character, seguido do campo padrão `Player.Team`. Se não houver dados suficientes e **Equipes** estiver ligado, o jogador com equipe desconhecida não será selecionado.
- Seleção de cabeça com alternativas UpperTorso, Torso e HumanoidRootPart para personagens com estrutura compatível.
- **Entrada: Auto / Mouse / Camera**. Auto prefere a função `mousemoverel` quando fornecida pelo executor em um PC sem entrada de toque; nos demais casos, usa Camera. O modo Mouse só atua com o mouse travado pelo jogo e pausa enquanto você digita em uma caixa de texto.
- Status de personagens detectados e equipes não identificadas para orientar o teste.
- Anti-Kick local opcional, inicialmente desligado, com os mesmos limites da versão anterior. Não impede banimentos ou expulsões do servidor.

O script trabalha com personagens associados a `Players`, com Humanoid vivo e partes reconhecidas. Alvos NPC do modo Zombies ou estruturas próprias do jogo fora desse modelo não foram implementados sem observação do cliente real.

## Teste no jogo

1. Entre no BloxStrike e aguarde uma partida com seu personagem vivo.
2. Execute o arquivo ou o carregador publicado. Mira, ESP e Anti-Kick começam desligados.
3. Ative **ESP** primeiro. Confira se os adversários são marcados e os aliados são excluídos com **Equipes: ON**.
4. Se aparecer **Equipe indefinida**, mantenha essa informação para diagnóstico. Desligar **Equipes** inclui qualquer outro jogador com personagem compatível; essa escolha é manual.
5. Ative **Mira**. No PC, confira **Entrada: Auto (Mouse)** se o executor disponibilizar a função. O jogo deve estar controlando o mouse, sem um menu ou caixa de texto em foco.
6. Se a mira por câmera tremer, experimente a opção **Mouse** quando estiver disponível. A sensibilidade real depende do jogo e ainda precisa de teste no aparelho.
7. Use **X** para encerrar. Você pode selecionar o modo de entrada pelo botão do painel e ajustar o FOV por **+/-**.

## Validação

A checagem de sintaxe e os 20 testes locais passaram. Os testes verificaram a resolução de equipes, a identificação de personagens e o cálculo do movimento de mira em simulação. A identificação real de equipes, a visibilidade dos personagens e o controle de mira no BloxStrike ainda precisam de teste dentro do jogo. Essas verificações locais não medem detecção nem risco de banimento.

## Carregador após a publicação

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/vicentzxx/vanta/main/Vanta_BloxStrike_Teste.lua"))()
```

O arquivo do Arsenal tem seu próprio endereço e esta adaptação é distribuída em outro arquivo.
