# VANTA BloxStrike — versão de teste 0.2

Arquivo: `Vanta_BloxStrike_Teste.lua`.

Esta adaptação usa o universo da [experiência BloxStrike](https://www.roblox.com/games/114234929420007/BloxStrike), identificado como `7633926880` pela API pública do Roblox. Ela aceita os places desse universo e interrompe a execução se estiver em outro jogo.

## O que mudou

- ESP com caixas, nomes e vida em uma sobreposição 2D atualizada a cada quadro. Esta versão substitui o contorno 3D da v0.1 e não depende da biblioteca Drawing do executor.
- Jogadores cuja equipe não foi identificada aparecem em amarelo, com **EQUIPE ?**. Com o filtro de equipes ligado, a mira continua excluindo esses jogadores; desligar o filtro é uma escolha manual.
- **Força da mira** ajustável de 20% a 100%, começando em 85%. No modo Camera, 100% aponta diretamente para a posição atual do alvo elegível. Valores inferiores mantêm uma transição suavizada.
- Atualização da mira no fim da ordem de renderização e retenção do alvo atual enquanto ele permanecer válido, visível e dentro do FOV. A resposta do controle de câmera do jogo ainda precisa ser observada em um cliente real.
- Contadores **ESP: desenhados/compatíveis** e **Equipe ?: quantidade** para orientar o diagnóstico.
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
3. Confirme que o título do painel mostra **v0.2**. Ative **ESP** e confira as caixas: vermelho para oponentes conhecidos; amarelo com **EQUIPE ?** para jogadores sem equipe identificada. Aliados conhecidos são excluídos com **Equipes: ON**.
4. Role o painel para ver o status. Informe o contador **ESP: desenhados/compatíveis** e o número de **Equipe ?** se o problema persistir. Desligar **Equipes** inclui qualquer outro jogador com personagem compatível; essa escolha é manual.
5. Ative **Mira**. No PC, confira **Entrada: Auto (Mouse)** se o executor disponibilizar a função. O jogo deve estar controlando o mouse, sem um menu ou caixa de texto em foco.
6. No celular, use **Entrada: Auto (Camera)** ou selecione **Camera**. Se quiser comparar uma mira mais direta, aumente **Força** até **100%** pelos botões ao lado desse valor. A alteração não aumenta o FOV e continua dependendo de um alvo elegível.
7. No PC, se a mira por câmera tremer, experimente a opção **Mouse** quando estiver disponível. A sensibilidade real depende do jogo e ainda precisa de teste no aparelho.
8. Use **X** para encerrar. Você pode selecionar o modo de entrada pelo botão do painel e ajustar o FOV por **+/-**.

## Validação

A validação local cobre a sintaxe, a resolução de equipes, a identificação de personagens, os cálculos de mira e de caixas 2D e a retenção de alvo em simulação. O relato do teste real da v0.1 indicou ESP ausente e mira fraca no celular. As alterações da v0.2 ainda precisam de um novo teste dentro do jogo; testes locais não comprovam resultado visual, detecção ou risco de banimento.

## Carregador após a publicação

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/vicentzxx/vanta/main/Vanta_BloxStrike_Teste.lua?v=0.2"))()
```

O arquivo do Arsenal tem seu próprio endereço e esta adaptação é distribuída em outro arquivo.
