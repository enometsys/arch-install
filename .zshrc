# Misc
export EDITOR=vim
export VISUAL=vim
export PATH=$PATH:`yarn global bin`
alias xclip="xclip -selection clipboard"

# Lines configured by zsh-newuser-install
HISTFILE=~/.histfile
HISTSIZE=1000
SAVEHIST=1000
unsetopt autocd
bindkey -v
# End of lines configured by zsh-newuser-install
# The following lines were added by compinstall
zstyle :compinstall filename "/home/$USER/.zshrc"

autoload -Uz compinit
compinit
# End of lines added by compinstall

# Antigen
export SPACESHIP_KUBECONTEXT_SHOW=false
export NVM_LAZY_LOAD=true
source /usr/share/zsh/share/antigen.zsh
antigen bundle lukechilds/zsh-nvm
antigen use oh-my-zsh
antigen theme https://github.com/denysdovhan/spaceship-zsh-theme spaceship
antigen bundle command-not-found
antigen bundle zsh-users/zsh-syntax-highlighting
antigen apply
