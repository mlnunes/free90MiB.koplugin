# Estratégia de versionamento

## Fonte de verdade

- O repositório GitHub `mlnunes/free90MiB.koplugin` é a fonte de verdade do código.
- `main` deve permanecer instalável e conter apenas alterações revisadas e testadas.
- O diretório `free90MiB.koplugin/` contém o plugin; `/mnt/us/koreader/free90MiB/` no Kindle contém apenas os arquivos de enchimento e não deve ser versionado.

## Branches e mudanças

- Para cada trabalho, criar uma branch curta a partir de `main`, por exemplo `feat/progress-ui`, `fix/df-parser` ou `docs/install`.
- Manter cada branch focada em uma mudança e integrá-la em `main` após revisão. Para um projeto individual, a revisão pode ser feita pelo próprio mantenedor antes do merge.
- Evitar desenvolver diretamente em `main`, exceto para correções urgentes e pequenas.
- Não reescrever histórico já publicado; usar novos commits para corrigir mudanças enviadas.

## Commits

Usar mensagens curtas e descritivas, de preferência no formato `<tipo>: <descrição>`:

- `feat:` funcionalidade compatível nova;
- `fix:` correção;
- `test:` testes;
- `docs:` documentação;
- `refactor:` reorganização sem mudança de comportamento.

Exemplos: `feat: add cancellable fill progress` e `fix: validate filler file sequence`.

## Versões e releases

Adotar versionamento semântico (`MAJOR.MINOR.PATCH`) e tags Git anotadas com o prefixo `v`:

- `MAJOR`: mudança incompatível na API pública ou no comportamento configurado;
- `MINOR`: funcionalidade compatível nova;
- `PATCH`: correção compatível ou ajuste de documentação sem mudança de API.

Enquanto o plugin não tiver sido validado em um Kindle com a versão-alvo do KOReader, manter as mudanças em desenvolvimento sem publicar uma versão estável. A primeira release estável deve receber a tag `v1.0.0` somente após cumprir os critérios abaixo. Não mover nem reutilizar tags de release; publicar uma versão seguinte para correções.

Cada release deve incluir notas com as mudanças, compatibilidade testada e limitações conhecidas. O pacote instalável deve conter o diretório `free90MiB.koplugin/` com `_meta.lua`, `main.lua` e os módulos do plugin; não deve conter dados de usuário nem arquivos `trashNNNNN.bin`.

## Verificações antes de integrar ou publicar

Executar localmente:

```sh
luajit tests/test_manager.lua
luajit tests/test_api.lua
```

Além dos testes simulados, uma release exige teste manual no Kindle/KOReader para verificar:

1. instalação e carregamento do plugin;
2. medição de `/mnt/us` e criação dos nomes sequenciais;
3. arquivos completos de 20 MiB e último arquivo parcial;
4. liberação e normalização nos limites de 70–90 MiB;
5. barra de progresso, cancelamento e recuperação de erros de `dd`/espaço insuficiente;
6. API chamada por outro plugin e retorno à faixa após o uso do espaço.

## Sincronização

Após integrar uma alteração validada, enviar `main` para `origin`. Para publicar uma release, criar a tag anotada na revisão aprovada e enviá-la ao GitHub; então criar uma GitHub Release com as notas e o pacote instalável.
