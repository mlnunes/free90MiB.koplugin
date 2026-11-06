# Free 90 MiB (KOReader plugin)

Plugin KOReader para Kindle que ajusta o espaço livre em `/mnt/us` usando somente arquivos próprios dentro de:

```text
/mnt/us/koreader/free90MiB/
```

Os arquivos gerenciados são `trash00000.bin` até `trash99999.bin`. Todos, exceto o de maior número, têm 20 MiB; o último pode ser parcial. Arquivos com outros nomes não são alterados.

## Instalação

Copie o conteúdo desta pasta para uma pasta chamada `free90MiB.koplugin` dentro de `koreader/plugins/`. No Kindle, o caminho ficará normalmente assim:

```text
/mnt/us/koreader/plugins/free90MiB.koplugin/
```

Reinicie o KOReader e habilite o plugin, se necessário. A pasta de dados é criada quando o plugin é carregado. O carregamento **não** preenche o armazenamento automaticamente.

## Uso

No menu do KOReader, escolha **Free 90 MiB**. A tela permite:

- normalizar o espaço livre para a faixa de 70–90 MiB;
- solicitar a liberação de espaço, em MiB;
- acompanhar o andamento numa barra de progresso e cancelar entre etapas de gravação/remoção.

A normalização cria enchimento quando há mais de 90 MiB livres e remove arquivos do plugin quando há menos de 70 MiB livres. Se não houver arquivos próprios suficientes para recuperar a faixa, a operação falha sem apagar dados de outros diretórios.

## API para outros plugins

Após o carregamento dos plugins pelo KOReader, outro plugin pode carregar o módulo compartilhado:

```lua
function OtherPlugin:onNeedSpace()
    -- Require lazily after KOReader has loaded its plugins and module paths.
    local Free90MiB = require("free90mib_api")
    local handle, err = Free90MiB.release_space(25 * Free90MiB.MIB,
        function(progress)
            -- progress.percentage, progress.current_free_bytes,
            -- progress.file_name, progress.phase
        end,
        function(success, result)
            if success then
                -- Faça aqui a operação que precisa do espaço liberado.
                -- Chame Free90MiB.reconcile(...) depois para voltar à faixa.
            end
        end
    )
    if not handle then
        -- err explica por que a operação não começou.
    end
end
```

Funções exportadas:

- `get_status()` — retorna `free_bytes`, `managed_bytes` e os arquivos gerenciados;
- `release_space(bytes, on_progress, on_done)` — remove arquivos de enchimento até liberar pelo menos a quantidade pedida;
- `reconcile(on_progress, on_done)` — ajusta para 70–90 MiB livres.

As operações são assíncronas e serializadas. `on_done(success, result)` recebe o resultado; `result.changed_bytes` indica a variação líquida observada no espaço livre. Como a liberação remove arquivos inteiros, pode liberar mais que o solicitado. O objeto retornado oferece `:cancel()`; alterações já concluídas permanecem e um arquivo parcial válido pode ficar como o último da série.

## Unidades e limites

MiB é binário: 1 MiB = 1.048.576 bytes. O espaço medido pode variar por blocos de alocação do sistema de arquivos ou por gravações simultâneas de outros processos. O plugin só modifica seus arquivos de enchimento; não pode garantir a faixa se outros dados consumirem o espaço e não houver arquivos próprios suficientes para remover.

## Testes locais

Com LuaJIT instalado:

```sh
luajit tests/test_manager.lua
luajit tests/test_api.lua
```

Os testes usam um armazenamento falso e não executam `dd` nem modificam `/mnt/us`.
