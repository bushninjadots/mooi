# mooi's terminal side panel: a column on the right of a kitty tab — the git panel on top (git-panel.sh,
# following the main pane's folder) and a companion underneath: a plain shell when Claude is what runs in
# the main pane, Claude when it is a shell. Run inside kitty as a kitten (kitty/side.conf binds it), so it
# needs no remote control:
#   kitten side.py           open the column (making whatever is missing), or hide it if it shows
#   kitten side.py close     close the column
# Hidden is kitty's stack layout: the main pane fills the tab and the column keeps running behind it, so
# a conversation with Claude is still there when it comes back.
import os

from kittens.tui.handler import result_handler

VAR = 'mooi_side'          # the user variable that marks the column's panes: git · mate
SHOWN = 'tall'             # the main pane on the left, the column on the right
WIDTH = 64                 # how much of the tab the main pane keeps, in percent


def main(args):
    pass


def side_of(w):
    return w.user_vars.get(VAR, '')


def runs_claude(w):
    for p in w.child.foreground_processes:
        cmd = p.get('cmdline') or []
        if cmd and os.path.basename(cmd[0]) == 'claude':
            return True
    return False


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    # kitty runs a kitten without __file__: its own path is the first argument
    here = os.path.dirname(os.path.abspath(os.path.expanduser(args[0]))) if args and args[0].endswith('.py') else os.path.expanduser('~/Projects/mooi/kitty')
    tab = boss.active_tab
    if tab is None:
        return
    windows = list(tab.windows)
    column = [w for w in windows if side_of(w)]
    others = [w for w in windows if not side_of(w)]
    if not others:
        return
    active = tab.active_window
    main_w = active if active in others else others[0]

    if args[1:2] == ['close']:
        for w in column:
            boss.mark_window_for_close(w)
        tab.goto_layout(SHOWN)
        return

    have = {side_of(w) for w in column}
    if column and tab._current_layout_name != 'stack' and have >= {'git', 'mate'}:
        # showing and whole: hide it (the main pane fills the tab, the column runs on behind it)
        tab.set_active_window(main_w)
        tab.goto_layout('stack')
        return

    tab.goto_layout(SHOWN)
    cwd = main_w.cwd_of_child or os.path.expanduser('~')
    env = ['--env', 'MOOI_SIDE=1', '--env', f'MOOI_SIDE_PID={main_w.child.pid}']
    # git straight after the main pane (the column's top), the companion last (its bottom)
    if 'git' not in have:
        boss.call_remote_control(main_w, (
            'launch', '--type=window', '--keep-focus', '--location=after', '--cwd', cwd, '--title', 'git',
            '--var', f'{VAR}=git', *env, os.path.join(here, 'git-panel.sh')))
    if 'mate' not in have:
        # Claude in the main pane: a shell beside it; a shell there: Claude beside it (a shell when it ends)
        if runs_claude(main_w):
            cmd, title = ['zsh', '-l'], 'terminal'
        else:
            cmd, title = ['zsh', '-lic', 'claude; exec zsh -l'], 'claude'
        boss.call_remote_control(main_w, (
            'launch', '--type=window', '--keep-focus', '--location=last', '--cwd', cwd, '--title', title,
            '--var', f'{VAR}=mate', *env, *cmd))
    # the main pane first (tall puts the first window on the left), at its width
    tab.set_active_window(main_w)
    # (only when it is not there yet: tall's `bias` with one number toggles it with 50, and resetting it
    # would undo a resize made by hand)
    opts = getattr(tab.current_layout, 'layout_opts', None)
    if opts is not None and getattr(opts, 'bias', WIDTH) != WIDTH:
        tab.layout_action('bias', [str(WIDTH)])
    tab.relayout()

