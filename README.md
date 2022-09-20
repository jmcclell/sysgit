# sysgit

sysgit helps you manage your user configuration files across multiple systems.


# What is it?

sysgit isn't actually a separate program in and of itself, it's just a method
for configuring a bare git repository to manage a subset of files in your
`$HOME` directory.

The idea for this came from: https://www.atlassian.com/git/tutorials/dotfiles

This repository contains an installation script which will set up things up. It
expects to be passed the location of a git repository containing your
configuration files and will set up the bare repository appropriately. It will
also configure an alias `sysgit` which will allow you to conveniently work with
this particular git repo from anywhere.

# Quickstart

## Installation

`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jmcclell/sysgit/HEAD/install.sh)"`

### Installation Options

To augment the behavior of the installation script, you can export several
environment variables to be made available when the script executes.

```sh
# The URL to the git repository used as the canonical storage for your system
# configuration files, i.e. your dotfiles repo
export SYSGIT_CONFIG_REPO="..."
# The name of the config repo branch to clone. [Default: master]
export SYSGIT_CONFIG_REPO_BRANCH="..."
# Set this to make the installation non-interactive for remote installs [Default: unset]
export NONINTERACTIVE=1
# The desired location of the bare repository clone of the configuration repository. [Default: $HOME/.sysgit]
export SYSGIT_HOME="..."
# The path to the location you wish sysgit to manage. [Default: $HOME]
export SYSGIT_WORKSPACE="..."
# The path to install the sysgit executable script. [Default: /usr/local/bin]
export SYSGIT_EXECUTABLE_PATH="..."

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jmcclell/sysgit/HEAD/install.sh)"
```

## Usage

Under the hood, sysgit is just git. It ties your `$HOME` directory (by default)
to a specified git repo, managing only the files that you specify in the git
repo and ignoring all other files unless specifically added by you using the
usual git workflow.

So, given a configuration repo with the following structure

```
Root
├── .config
│  └── nvim
│     └── init.lua
├── .zshrc
```

sysgit will ensure that your `$HOME` directory contains those files from the
configured branch of the configuration repo at installation time.

To pull the latest remote changes:

`sysgit pull`

To commit local changes to e.g. `$HOME/.zshrc`:

```sh
sysgit add $HOME/.zshrc
sysgit commit -m "Updated ZSH configuration"
```

To make local commits available to be pulled by other systems synced to the
same configuration repository:

`sysgit push`

As you can see, the workflow is just git. Nothing more. All your usual git workflows work exactly the same way as usual, except the repository is tucked away into a bare repository, your workspace is set to `$HOME` regardless of your current working directory, and any files that aren't explicitly added to git are ignored by all its subcommands including e.g.

`sysgit status`

# How does it work?

sysgit takes advantage of several git features: bare repositories, the ability
to set `--work-tree` at git command invocation time, and the ability to
configure a local repository to ignore untracked files.

The following demonstrates the basic setup, though this installation script's
actual installation is a bit more complex.

```sh
# Clone a bare repository
git clone --bare $GIT_REPO_LOCATION $HOME/.sysgit

# Create an alias which invokes git with the necessary directory information
alias sysgit='$(command -v git) --git-dir=$HOME/.sysgit/ --work-tree=$HOME'

# Ensure that untracked files under $HOME are not shown when working with
# sysgit commands. Only files contained in the configuration repository should be
# shown.
sysgit config --local status.showUntrackedFiles no
```

# Why this installation script?

While the setup is simple enough, it's nice to have a reliable way of
initializing the sysgit concept on any machine in a way that

1. works for both Linux and macOS
2. works with any configuration repository
3. handles pre-existing configuration files sanely

That last point needs some explanation. When you have an existing system, it's
likely that one or more files in your configuration repo will already be
present, e.g. `$HOME/.vimrc` may already exist. This will prevent the `git
checkout` command from working, as it will infer the pre-existing file as
"local changes."

To fix that issue, this script will back up all colliding files into
`$HOME/.config-backup.$UNIX_TIMESTAMP/`

# bootstrap file

Along with initializing sysgit, this installation script can also execute a
bootstrap file named `.sysgit-bootstrap` located at the root of your
configuration repository. This script will be executed with bash from the
installation script and can be used for any bootstrapping tasks, e.g.
installation of software.

It is recommended that any bootstrap script you create contain internal logic
to detect OS and to assume a non-interactive mode so that you may use it for
automated machine bootstrapping, e.g. ensuring you always have your preferred
configuration within development Docker images.

It is also recommended to make your bootstrap script idempotent so that it can
be safely be ran more than once. This helps if you ever want to re-install
sysgit from scratch or need to sync changes to the bootstrap file from another
machine.

# configuration repo

Your configuration repo should mirror your $HOME directory, containing only the
files you wish to manage. An example configuration repository structure might
look like:

```
Root
├── .config
│  └── nvim
│     └── init.lua
├── .zshrc
├── .zprofile
└── .sysgit-bootstrap
```

If you don't have an existing repository for your local user configuration,
then simply create an empty repository on e.g. Github and point sysgit to
that. Once sysgit is installed, you can then start adding your local config
files using the usual `sysgit add` / `sysgit commit` workflow and build up
your configuration repo from there.

# Secrets

It is not recommended to commit secrets (e.g. private keys, API keys) in plain
text, even if your repository is hosted as a private repo. You should employ some
sort of proper secrets workflow to synchrnoize them. This is out of scope for this
README.

# Uninstalling

Removing sysgit is as simple as deleting the bare repository directory (by default
located at `$HOME/.sysgit`) and removing the sysgit script (by default located at
`$HOME/.local/bin/sysgit`). That's it.
