# Mothership reconciler binary installation

Prerequesites:
- git
- make
- golang

1. Clone repository

```
git clone https://github.com/kyma-incubator/reconciler.git
```

2. Build binary

Navigate to the directory with the cloned sources and call make to build binary.

- linux

```
cd ./reconciler \
&& make build-linux
```

- macOS

```
cd ./reconciler \
&& make build-darwin
```

3. Add binary to the `PATH` environmental variable

- for `bash` shell 

```
export PATH=$PATH:$(pwd)/cmd/mothership > $HOME/.bashrc
```

- for `zsh` shell

```
export PATH=$PATH:$(pwd)/cmd/mothership > $HOMR/.zshrc

