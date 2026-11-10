# VANTA BloxStrike — versão de teste 0.3

Arquivo: `Vanta_BloxStrike_Teste.lua`.

Esta adaptação usa o universo da [experiência BloxStrike](https://www.roblox.com/games/114234929420007/BloxStrike), identificado como `7633926880` pela API pública do Roblox. Ela aceita os places desse universo e interrompe a execução se estiver em outro jogo.

## O que mudou

- ESP simplificado: apenas caixa vermelha e nome dos adversários, atualizado a cada quadro. Sem barra de vida ou distância e sem dependência da biblioteca Drawing.
- Mira e ESP usam o mesmo filtro de adversários. **CT** e **Counter-Terrorists** são reconhecidos como a mesma equipe; **T**, **Terrorists** e variantes também. Aliados, espectadores identificados e equipes desconhecidas não são selecionados.
- **Minha equipe** alterna entre **Auto**, **CT** e **T**. A escolha manual informa somente o seu lado para o filtro; ela não muda sua equipe dentro do jogo nem atribui uma equipe a jogadores desconhecidos.
- Equipes são lidas de atributos Team/TeamName/Side/Faction, do objeto padrão Player.Team e, como alternativa, de cores de equipe explícitas e diferentes das cores padrão neutras.
- **Camera** é a entrada padrão no PC e no celular. Isso evita escolher automaticamente uma função mousemoverel cuja semântica pode variar entre executores.
- **Força da mira** ajustável de 20% a 100%, começando em 100%. No modo Camera, 100% aponta diretamente para a posição atual do alvo elegível. Valores inferiores mantêm uma transição suavizada.
- Atualização da mira no fim da ordem de renderização e retenção do alvo atual enquanto ele permanecer válido, visível e dentro do FOV. A resposta do controle de câmera do jogo ainda precisa ser observada em um cliente real.
- Contadores **ESP: desenhados/compatíveis** e **Equipe ?: quantidade** para orientar o diagnóstico.
- Painel identificado como BloxStrike, com rolagem para telas menores.
- Leitura de personagens com Humanoid ou vida replicada por atributos Health/Alive, incluindo partes em submodelos. A v0.2 exigia um Humanoid direto e descartava outros formatos.
- Alternativas de modelo por nome exato de usuário ou UserId em contêineres Characters/Players/PlayerCharacters, quando Player.Character não resolve um modelo com partes reconhecidas.
- Seleção de Head/HeadHB com alternativas UpperTorso, Torso e HumanoidRootPart. Partes aninhadas em acessórios e ferramentas não são escolhidas pelo fallback recursivo.
- Mouse continua como alternativa manual, dependente do executor. O modo Mouse só atua com o mouse travado pelo jogo e pausa enquanto você digita em uma caixa de texto.
- Status de personagens detectados e equipes não identificadas para orientar o teste.
- Anti-Kick local opcional, inicialmente desligado, com os mesmos limites da versão anterior. Não impede banimentos ou expulsões do servidor.

O script trabalha com modelos associados a jogadores. Vida zero e Alive=false conhecidos são excluídos. Quando a vida não está disponível, ele pode usar um corpo mapeado ao jogador e não inventa um valor de HP; nesse caso não há confirmação independente de que aquele corpo esteja vivo. A ausência do corpo local em um FPS de primeira pessoa não bloqueia sozinha o caminho da mira. NPCs do modo Zombies não foram adaptados.

## Teste no jogo

1. Entre no BloxStrike e aguarde uma partida com seu personagem vivo.
2. Execute o arquivo ou o carregador publicado. Mira, ESP e Anti-Kick começam desligados.
3. Confirme que o título do painel mostra **v0.3**. Ative **ESP inimigos** e confira se somente adversários recebem caixa e nome em vermelho.
4. Se **Minha equipe** mostrar Auto (?), clique nesse botão até informar corretamente **CT** ou **T**. Estando em CT, somente T deve ser selecionado; estando em T, somente CT deve ser selecionado. A identificação do outro jogador continua sendo necessária.
5. Ative **Mira** e mantenha **Entrada: Camera** no primeiro teste, inclusive no Xeno. A força começa em **100%** e pode ser reduzida pelos botões próximos desse valor.
6. Role o painel para ver o status. Se ainda houver falha, informe **Jogadores / Modelos / Alvos com partes / Equipe ? / ESP**. Esses números ajudam a distinguir falhas de modelo, partes e equipe sem presumir que aumentar a força resolverá a ausência de alvos.
7. As opções Auto/Mouse continuam disponíveis para comparação, mas a resposta do mouse e da câmera depende da versão do jogo e do executor. A v0.3 precisa de teste real antes de afirmar compatibilidade.
8. Use **X** para encerrar. Você pode selecionar o modo de entrada pelo botão do painel e ajustar o FOV por **+/-**.

## Validação

A checagem de sintaxe e 50 testes locais passaram. Eles cobrem aliases CT/T, exclusão de aliados e espectadores, seleção manual do seu lado, alternativas de cor e modelos, vida por atributo, ausência de Humanoid, partes aninhadas, projeção 2D e controle de mira em simulação. A v0.3 ainda precisa de teste no BloxStrike; esses resultados não comprovam funcionamento visual, indetectabilidade ou proteção contra banimento.

## Carregador após a publicação

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/vicentzxx/vanta/main/Vanta_BloxStrike_Teste.lua?v=0.3"))()
```

O arquivo do Arsenal tem seu próprio endereço e esta adaptação é distribuída em outro arquivo.
