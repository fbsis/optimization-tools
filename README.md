# optimization-tools

Ferramentas pessoais para otimização de vídeos, imagens e movimentação de arquivos.

## Ferramentas incluídas

- `opt`
- `videoopt`
- `transcode-job`
- `imgopt`
- `filler`

---

## Visão geral

### `opt`

Comando central para acessar todas as ferramentas.

### `videoopt`

Envia vídeos para um LXC remoto, processa com FFmpeg usando GPU Intel via VAAPI e devolve o arquivo otimizado para a máquina de origem.

### `transcode-job`

Script executado dentro do LXC responsável pela conversão usando a GPU Intel.

### `imgopt`

Otimiza imagens JPG, JPEG, PNG e WEBP usando processamento paralelo.

### `filler`

Move arquivos da pasta atual para um volume VeraCrypt até atingir a margem de espaço livre configurada.

---

# Instalação

## 1. Instalação na VM cliente

Instale as dependências:

```bash
sudo apt update

sudo apt install -y \
    rsync \
    openssh-client \
    imagemagick
```

Instale os comandos:

```bash
sudo install -m 0755 opt /usr/local/bin/opt
sudo install -m 0755 videoopt /usr/local/bin/videoopt
sudo install -m 0755 imgopt /usr/local/bin/imgopt
sudo install -m 0755 filler /usr/local/bin/filler
```

Verifique:

```bash
which opt
which videoopt
which imgopt
which filler
```

---

# Configuração do transcoder

## 2. Instalação no LXC

O `videoopt` usa por padrão:

```text
IP: 192.168.1.116
Usuário: transcoder
```

No LXC, instale:

```bash
sudo apt update

sudo apt install -y \
    ffmpeg \
    vainfo \
    intel-media-va-driver
```

Instale o script:

```bash
sudo install -m 0755 transcode-job /usr/local/bin/transcode-job
```

Verifique:

```bash
ls -lah /usr/local/bin/transcode-job
```

---

## 3. Configuração da GPU Intel

O transcoder utiliza:

```text
/dev/dri/renderD128
```

Verifique se o device existe:

```bash
ls -lah /dev/dri
```

Teste o VAAPI:

```bash
vainfo \
    --display drm \
    --device /dev/dri/renderD128
```

O usuário `transcoder` precisa ter acesso ao device.

Exemplo:

```bash
sudo usermod -aG kvm transcoder
```

Depois faça logout/login do usuário ou reinicie a sessão.

Teste novamente:

```bash
sudo -u transcoder vainfo \
    --display drm \
    --device /dev/dri/renderD128
```

---

# Configuração SSH

## 4. Acesso da VM ao LXC

O `videoopt` precisa acessar o LXC sem pedir senha.

Na VM cliente:

```bash
ssh-keygen -t ed25519
```

Copie a chave:

```bash
ssh-copy-id transcoder@192.168.1.116
```

Teste:

```bash
ssh transcoder@192.168.1.116
```

O login deve funcionar sem pedir senha.

Teste também se o script remoto está disponível:

```bash
ssh transcoder@192.168.1.116 \
    "test -x /usr/local/bin/transcode-job && echo OK"
```

Resultado esperado:

```text
OK
```

---

# Uso

## `opt`

O comando principal é:

```bash
opt
```

Ele abre:

```text
==========================================
                 OPT
==========================================

  [1] VIDEO
  [2] IMAGE
  [3] FILLER
  [4] AJUDA
  [0] SAIR
```

Também é possível chamar diretamente:

```bash
opt video
opt video "arquivo.mp4"

opt image
opt imagem

opt filler
```

---

# Vídeos

## `videoopt`

### Processar um único vídeo

```bash
videoopt "video.mp4"
```

ou:

```bash
opt video "video.mp4"
```

### Processar a pasta atual

```bash
videoopt
```

ou:

```bash
opt video
```

Sem arquivo informado, o script procura vídeos recursivamente na pasta atual.

Formatos suportados:

```text
mp4
mkv
avi
mov
m4v
webm
mpg
mpeg
ts
mts
m2ts
wmv
```

Arquivos terminados em:

```text
-optimized.mp4
```

são ignorados na busca recursiva.

---

## Fluxo do `videoopt`

```text
VM cliente
    |
    | rsync
    v
LXC transcoder
192.168.1.116
    |
    | transcode-job
    v
FFmpeg
    |
    | Intel VAAPI
    v
H.264
    |
    | rsync
    v
VM cliente
```

O processo é:

1. O vídeo é enviado via `rsync`.
2. O LXC executa `transcode-job`.
3. O FFmpeg utiliza a GPU Intel.
4. O resultado é enviado novamente para a VM.
5. Os arquivos temporários no LXC são removidos.
6. O tamanho original e o tamanho convertido são comparados.

---

## Modos do `videoopt`

Ao executar:

```text
[1] Criar arquivo -optimized.mp4
[2] Substituir original
[3] Cancelar
```

### Criar arquivo otimizado

Exemplo:

```text
video.mp4
```

gera:

```text
video-optimized.mp4
```

### Substituir o original

O vídeo convertido substitui o arquivo original.

Quando necessário, o arquivo final passa a utilizar extensão:

```text
.mp4
```

### Proteção contra arquivos maiores

Se o arquivo convertido ficar maior ou igual ao arquivo original:

```text
convertido >= original
```

o resultado é descartado e o original permanece intacto.

---

## Configuração padrão do transcoder

```text
Codec de vídeo: H.264
Encoder: h264_vaapi
GPU: Intel
Device: /dev/dri/renderD128
Profile: High
QP: 23

Áudio:
Codec: AAC
Bitrate: 128 kb/s
```

---

## Logs do `videoopt`

Os logs ficam em:

```text
~/.local/share/videoopt/
```

Exemplo:

```text
~/.local/share/videoopt/videoopt-20261006-170000.log
```

---

# Imagens

## `imgopt`

Execute dentro da pasta que contém as imagens:

```bash
imgopt
```

ou:

```bash
opt image
```

Também funciona:

```bash
opt imagem
```

---

## Formatos suportados

```text
.jpg
.jpeg
.png
.webp
```

---

## Configuração padrão

JPEG:

```text
Qualidade: 82
```

WEBP:

```text
Qualidade: 82
```

PNG:

```text
Compressão: nível 9
Lossless
```

---

## Modos do `imgopt`

O script apresenta:

```text
[1] Criar diretório paralelo
[2] Substituir arquivos originais
[3] Cancelar
```

### Diretório paralelo

Se você estiver em:

```text
/media/fotos
```

o resultado será criado em:

```text
/media/fotos-optimized
```

A estrutura interna de diretórios é preservada.

### Substituir originais

Os arquivos otimizados substituem os arquivos atuais.

Antes da substituição, permissões e data de modificação são preservadas sempre que possível.

---

## Processamento paralelo

O `imgopt` detecta:

```bash
nproc
```

e sugere aproximadamente metade dos cores disponíveis.

Exemplo:

```text
CPU: 12 cores
Workers sugeridos: 6
```

É possível informar outro número de workers durante a execução.

---

## Proteção contra arquivos maiores

Se a imagem otimizada ficar maior ou igual ao arquivo original:

```text
otimizado >= original
```

o arquivo otimizado é descartado.

No modo de diretório paralelo, o arquivo original é copiado para manter a estrutura completa.

---

## Logs do `imgopt`

```text
~/.local/share/imgopt/
```

Exemplo:

```text
~/.local/share/imgopt/imgopt-20261006-170000.log
```

---

# Filler

## `filler`

O `filler` move os arquivos da pasta atual para:

```text
/media/veracrypt64
```

Execute dentro da pasta de origem:

```bash
filler
```

ou:

```bash
opt filler
```

---

## Exemplo

```bash
cd /media/origem
filler
```

O script mostra:

```text
ORIGEM:
  /media/origem

DESTINO:
  /media/veracrypt64
```

e pede confirmação antes de mover qualquer arquivo.

---

## Margem de segurança

O script mantém:

```text
512 MiB
```

livres no volume de destino.

Quando o volume atinge essa margem, o processo termina.

---

## Arquivos que não cabem

Se um arquivo for maior que o espaço disponível, ele é ignorado.

O script continua procurando arquivos menores que ainda possam caber no volume.

Isso permite aproveitar melhor o espaço restante.

---

## Movimentação

Quando origem e destino estão no mesmo filesystem:

```bash
mv
```

é utilizado.

Quando estão em filesystems diferentes:

```bash
rsync \
    -a \
    --whole-file \
    --remove-source-files
```

é utilizado.

---

## Estrutura de diretórios

A estrutura relativa da origem é preservada.

Exemplo:

```text
origem/
├── fotos/
│   └── foto.jpg
└── docs/
    └── arquivo.pdf
```

vira:

```text
/media/veracrypt64/
├── fotos/
│   └── foto.jpg
└── docs/
    └── arquivo.pdf
```

---

## Diretórios vazios

Ao terminar, o `filler` remove diretórios vazios restantes