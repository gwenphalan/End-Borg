# Node 24.18.0, installed under ~/.local/opt and symlinked into ~/.local/bin.
# Prepended so it wins over /usr/local/bin, which still points at Node 22.22.1
# in /opt. That older tree is left intact because it hosts the globally
# installed CLIs (claude-code, codex, gemini, auggie, ocx, opencode-ai); those
# use `#!/usr/bin/env node`, so they now resolve to 24 via this path entry.
# To undo: delete this line and ~/.local/bin/{node,npm,npx,corepack}.
fish_add_path --prepend ~/.local/bin

# Commands to run in interactive sessions can go here
if status is-interactive
    # No greeting
    set fish_greeting

    # Use starship
    function starship_transient_prompt_func
        starship module character
    end
    if test "$TERM" != "linux"
        starship init fish | source
        enable_transience
    end
    
    # Colors
    if test -f ~/.local/state/quickshell/user/generated/terminal/sequences.txt
        cat ~/.local/state/quickshell/user/generated/terminal/sequences.txt
    end

    # Aliases
    # kitty doesn't clear properly so we need to do this weird printing
    alias clear "printf '\033[2J\033[3J\033[1;1H'"
    alias celar "printf '\033[2J\033[3J\033[1;1H'"
    alias claer "printf '\033[2J\033[3J\033[1;1H'"
    alias pamcan pacman
    alias q 'qs -c ii'
    alias antigrav 'agy --dangerously-skip-permissions --mode accept-edits'
    alias icons '/home/gwenp/.local/bin/kitty-icons'
    if test "$TERM" != "linux"
        alias ls 'eza --icons=auto'
    end
    if test "$TERM" = "xterm-kitty"
        alias ssh 'kitten ssh'
    end
end
