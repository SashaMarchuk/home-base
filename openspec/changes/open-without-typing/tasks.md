## 1. Build
- [x] 1.1 `be_open` creates the tab or window with the launch command and types nothing; `launch_tab` wraps the launch line (login shell, hex) for `open`, `resume` and `thaw`
- [x] 1.2 The focus is given back in the same script; the app is never activated
- [x] 1.3 The recorded process is the launch command by name (a fixture with a shell on the tty that holds the session id)
- [x] 1.4 The resume line recorded at `open` names the session file's profile when `launch.profile.<role>` is unset
- [x] 1.5 Fake-backend tests: a launch line with quotes, a failing create, the focus given back, a command of another shape refused; the AppleScript test compiles the new block and checks it types nothing and never activates
- [x] 1.6 Real-tab check on throwaway tabs (run on a real terminal; five faults found and fixed, see the scenarios on a new window, no current window, a resumed session of a group and a late redraw): a tab opens while keys are typed elsewhere and starts its session; the focus stays; `close`, `park` and `resume` work on it; the profile is in the recorded resume line
