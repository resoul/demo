# Adding the mascot `.riv` file

`MascotLoginViewController` loads `login_mascot.riv` from the app bundle and drives its state machine
`Login Machine`. Without the file the form still works and the mascot area shows a hint.

## 1. Get a file

- Make your own in the Rive editor (rive.app), or remix a community file. The classic choice is the
  "Login Teddy" / "Teddy login" bear (search "teddy login" on rive.app/community).
- Check the license of community files before shipping them.
- In the editor, use **Export → Download → Runtime (.riv)**.

## 2. Add it to the project

1. Rename the file to `login_mascot.riv` (or set `MascotRig.fileName` to your file's name, without the extension).
2. Put it in `controller/MascotLogin/`.
   This project uses Xcode synchronized folders, so any file in `controller/` is bundled automatically, with no
   "Add Files" step. In older projects, drag it into Xcode and tick the **controller** target in
   "Add to targets".
3. To check that it's bundled, open the target's **Build Phases → Copy Bundle Resources**, or build and look
   for `login_mascot.riv` inside `controller.app`.

## 3. Match the input names

Open the file in the Rive editor → **State Machine** → **Inputs** panel and compare with `MascotRig`:

| `MascotRig` property | Default        | Type    | Used for                                     |
|----------------------|----------------|---------|----------------------------------------------|
| `stateMachine`       | `Login Machine`| —       | State machine name                           |
| `lookInput`          | `numLook`      | Number  | 0…100, caret position in the email field     |
| `coverEyesInput`     | `isChecking`   | Boolean | `true` while the password field is focused   |
| `peekInput`          | `isPeeking`    | Boolean | `true` while the password is shown           |
| `lookingInput`       | `nil`          | Boolean | `true` while the email field is focused      |
| `successTrigger`     | `trigSuccess`  | Trigger | Sign In with valid-looking input             |
| `failTrigger`        | `trigFail`     | Trigger | Sign In with invalid input                   |

Inputs that don't exist in the file are ignored (Rive's `setInput` is a no-op for unknown names), so a
mismatch shows up as "the mascot doesn't react", not as a crash.

### Teddy login file

In the Teddy file the names mean something slightly different: `isChecking` makes the bear *look at the text*
(and enables `numLook`), `isHandsUp` covers the eyes, and there is no peek input. Use:

```swift
let login = MascotLoginViewController(rig: MascotRig(
    coverEyesInput: "isHandsUp",
    peekInput: nil,
    lookingInput: "isChecking"
))
```

## 4. Show it

```swift
navigationController?.pushViewController(MascotLoginViewController(), animated: true)
```

In the demo app it opens with the **Login** button on the first screen.
