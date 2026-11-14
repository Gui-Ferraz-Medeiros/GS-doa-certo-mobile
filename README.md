# DoaCerto Mobile

Aplicativo Flutter que conecta pessoas e empresas a campanhas de doação e instituições. Disponível para Android e Web.

## Principais funcionalidades

- Cadastro e login demonstrativos, com perfis de doador e empresa.
- Consulta, oferta e cadastro de doações, incluindo agendamento e comprovante.
- Mapa de instituições e campanhas, com indicadores de prazo e acesso a rotas.
- Assistente com recomendações de instituições e itens aceitos.
- Painéis territoriais sobre recursos, clima e serviços, com alertas explicáveis.
- Acessibilidade com alto contraste e ajuste do tamanho do texto.

O app usa uma API Express para consultar organizações e conversar com o assistente. Doações, contas demonstrativas, preferências e histórico ficam armazenados localmente. Os indicadores de clima e procura são sintéticos; alertas apoiam a análise e não substituem fontes oficiais nem decisões humanas.

## Executar

Requer Flutter instalado. Na raiz do projeto:

```powershell
flutter pub get
flutter run -d chrome --dart-define=DOACERTO_API_URL=https://doacerto-mobile-api.onrender.com
```

Para gerar o APK de release:

```powershell
flutter build apk --release --dart-define=DOACERTO_API_URL=https://doacerto-mobile-api.onrender.com
```

Baixe o APK publicado: [DoaCerto Mobile 1.0.0](https://github.com/Gui-Ferraz-Medeiros/GS-doa-certo-mobile/releases/download/v1.0.0/app-release.apk).

O serviço remoto pode demorar na primeira chamada após um período sem uso. Para executar a API localmente, consulte `deployment/api`.

## Acesso demonstrativo

Conta de teste: `maria@doacerto.com` · senha: `123456`.

Também é possível criar uma conta pelo app. A autenticação é apenas demonstrativa: os dados ficam neste aparelho e não há verificação por e-mail. Não use informações ou senhas reais.

## Equipe e entrega

- Guilherme Ferraz de Medeiros — RM 564743
- Roberto Marques Moreira — RM 564935
- Gabriel Jorge Coutinho — RM 565441
- Repositório: [GS-doa-certo-mobile](https://github.com/Gui-Ferraz-Medeiros/GS-doa-certo-mobile)
- Vídeo de demonstração: pendente de publicação.
