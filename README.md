# DoaCerto Mobile

Aplicativo Flutter para conectar doações a instituições e explorar indicadores territoriais de recursos, clima e serviços. O projeto demonstra integração com API, persistência local, navegação nomeada e alertas explicáveis.

## Problema e público

O DoaCerto busca facilitar a destinação de doações por pessoas e empresas e ajudar instituições a encontrar recursos. O app mobile foi criado para doadores e empresas que precisam consultar campanhas, localizar organizações e acompanhar agendamentos.

## Funcionalidades

- Login demonstrativo com perfil de doador ou empresa.
- Dashboard com quantidade de doações e itens marcados como entregues.
- Três painéis territoriais (recursos e doações, clima local e serviços/demanda), com séries históricas e navegação nomeada que recebe o território selecionado.
- Termômetro territorial por localização cadastrada: vermelho para prazo vencido ou em até 3 dias, amarelo de 4 a 7 dias, verde acima de 7 dias e cinza quando não há prazo.
- Mapa OpenStreetMap com organizações carregadas do backend, agrupamentos coloridos de urgência e links para navegação.
- Chat com o assistente, recomendações de instituições e rota.
- Cadastro de doações, agendamento opcional de entrega/recolhimento e comprovante digital copiável.
- Alto contraste, ajuste de tamanho do texto e aviso/controle de consentimento.
- Persistência local de doações, preferências e histórico do chat.

## Dados, indicadores e limitações

- As doações do app Flutter são registros locais de demonstração e ficam armazenadas com `SharedPreferences`.
- As organizações são obtidas de `GET /api/dados` do backend DoaCerto e incluem endereço e coordenadas.
- O painel de recursos usa os registros locais filtrados pelo território selecionado. O painel climático e o índice histórico de procura por serviços são séries sintéticas de demonstração, não dados observados nem previsões oficiais.
- Os alertas mostram evidência, grau de confiança qualitativo e limitações. A confiança é baixa quando a série é sintética ou a cobertura cadastral é limitada; alertas não tomam decisões automáticas.
- O indicador **itens entregues** soma as quantidades registradas nas doações marcadas como entregues. Não representa peso ou número de pessoas beneficiadas.
- O termômetro é uma regra determinística baseada no prazo final informado; não é uma previsão estatística de demanda. A confiabilidade depende da precisão dos prazos e endereços cadastrados. Círculos indicam localização aproximada do grupo, não uma área geográfica medida.
- O app não estima CO₂ evitado nem quilogramas de alimentos porque a base atual não registra massa, composição ou fatores de conversão verificáveis.
- As cores apoiam a priorização; a decisão final sobre campanhas e logística é humana.

## Privacidade e acessibilidade

O app não coleta a localização do dispositivo. O diálogo de consentimento informa que, caso a função de proximidade seja ativada, a localização seria usada apenas para calcular pontos próximos e não seria armazenada ou compartilhada. A preferência de consentimento fica no armazenamento local e pode ser alterada em Perfil. O app também oferece alto contraste e texto ampliável.

## Tecnologias e decisões

- Flutter/Dart 3.13.7 ou superior (testado com Flutter 3.47.9 e Dart 3.13.7); Android e Web são os alvos nativos configurados neste repositório.
- Provider para estado compartilhado entre telas.
- `SharedPreferences` para persistência local e uso dos dados existentes sem rede.
- `http` para consumir a API Express local.
- `flutter_map` e OpenStreetMap para o mapa; a camada de círculos é derivada de prazos já cadastrados.
- `url_launcher` para abrir rotas no Google Maps.

## Executar localmente

Para iniciar a API local com o assistente:

```powershell
cd deployment/api
npm ci
Copy-Item .env.example .env
# Edite .env localmente e preencha GEMINI_API_KEY; nunca versione esse arquivo.
npm start
```

O arquivo `.env` está excluído do Git. Em outro terminal, inicie o app Flutter:

```powershell
cd C:\caminho\para\doacerto_mobile
flutter pub get
flutter run --dart-define=DOACERTO_API_URL=http://localhost:3001
```

No emulador Android, use `http://10.0.2.2:3001`; para um dispositivo físico, use o endereço LAN do computador. HTTP é permitido apenas no build Android debug.

## Publicar a API remota no Render

O arquivo `render.yaml` configura um serviço Node no plano Free, com diretório isolado em `deployment/api`, verificação de saúde e implantação automática da branch `main`.

1. Envie as alterações deste repositório ao GitHub.
2. No Render, crie um **Blueprint** usando a URL pública `https://github.com/Gui-Ferraz-Medeiros/GS-doa-certo-mobile`. O Render lê o `render.yaml` da raiz e solicita a criação do serviço `doacerto-mobile-api`.
3. No painel do serviço, configure `GEMINI_API_KEY` como variável secreta. Nunca coloque a chave neste repositório, no Flutter, em `--dart-define` ou em mensagem de chat. Verifique a cota e eventuais cobranças no provedor de IA.
4. Aguarde o deploy e confirme que `https://doacerto-mobile-api.onrender.com/health` retorna `{"status":"ok"}`. A API publica apenas os campos necessários das organizações e os endpoints de chat/status; não expõe o endpoint de gravação do servidor web.
5. Gere os builds apontando para a URL HTTPS criada:

```powershell
flutter build apk --release --dart-define=DOACERTO_API_URL=https://doacerto-mobile-api.onrender.com
flutter build web --dart-define=DOACERTO_API_URL=https://doacerto-mobile-api.onrender.com
```

O plano Free pode suspender o serviço após inatividade; a primeira requisição depois da suspensão pode demorar cerca de 50 segundos. O repositório foi conectado como URL pública, sem autorização da integração GitHub: o Render não fará deploy automático de novos commits. Após enviar mudanças, execute uma sincronização manual do Blueprint ou conecte a conta GitHub no Render. Sem `GEMINI_API_KEY`, organizações e indicadores locais continuam acessíveis, mas o assistente retorna uma mensagem explícita de indisponibilidade.

O diretório de organizações é uma cópia reduzida da base de demonstração já usada no projeto DoaCerto. Confirme endereço, coordenadas e itens aceitos diretamente com cada instituição antes de uma doação; esses dados não garantem disponibilidade atual.

## Executar os testes

Na raiz Flutter:

```powershell
flutter analyze
flutter test
```

Para a API:

```powershell
cd deployment/api
npm ci
npm test
```

## Equipe e links de entrega

- Guilherme Ferraz de Medeiros — RM 564743
- Roberto Marques Moreira — RM 564935
- Gabriel Jorge Coutinho — RM 565441
- Repositório: [GS-doa-certo-mobile](https://github.com/Gui-Ferraz-Medeiros/GS-doa-certo-mobile)
- Vídeo de demonstração: pendente de publicação (até 3 minutos, acesso público)

## Checklist de entrega acadêmica

- [x] Informar nomes completos e RMs de todos os integrantes no arquivo `entrega.txt`.
- [x] Link do repositório GitHub informado.
- [ ] Gravar e publicar o vídeo de demonstração (até 3 minutos), com acesso público.
- [ ] Incluir capturas das telas em `assets/screenshots/`.
- [ ] Gerar e disponibilizar o APK de release em GitHub Releases; para integração remota, usar backend HTTPS configurado no build.
