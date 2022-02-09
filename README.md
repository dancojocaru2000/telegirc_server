# telegirc_server

An IRC server providing an interface to Telegram.

## Manual

Until some help will be added, this will serve as a very basic manual.

### HTTP

Connecting to TelegIRC via HTTP (not HTTPS) is supported, but not encouraged.
HTTP transmits all traffic in plain text, so anybody on the network can inspect it and read the contents.

Since old devices don't have HTTPS, restricting TelegIRC to HTTPS would render it useless.

However, registering via HTTP is not supported. Please use a modern computer and a modern IRC client (or [Kiwi IRC](https://kiwiirc.com/)) to register, then you may use an old, HTTP only IRC client.

### #a

Since anybody logging in using your nickname can access your Telegram account through TelegIRC, you can protect your account by setting a password with #a.

After setting the password, you can configure your IRC client to send that password using `/PASS` when connecting to automatically login.

### #telegirc-logout

To completely remove all your data from TelegIRC, join #telegirc-logout and follow the instructions.

This will delete **all the data** that TelegIRC stored associated with your nickname.

**WARNING:** If you logged in the same Telegram account from multiple TelegIRC nicknames, #telegirc-logout will only remove the data associated with the current nickname. Other nicknames logged in the same Telegram account will **not** be logged out.

### #telegirc-settings

Join #telegirc-settings to change settings about TelegIRC.

### #telegirc-dir

Join #telegirc-dir to see your Telegram chats and what channels you can join to talk.

As a general rule, anything with a username can be talked on by joining `#@username`. If a user doesn't have a username set, you'll need to use #telegirc-dir to find the channel to join.

`chats main` will list the chats you normally see when opening the Telegram app, and `chats archive` will list the chats you archived.

If you provide any text after `chats main` or `chats archive`, it will be used to filter the listing. For example, `chats main m` will only list chats containing the letter `m`, such as `Jim` or `Mary`. The search is case insensitive.

### Chatting

While in a chat, any* message you send will be sent as a Telegram message. IRC formatting is likely[^1] supported and converted to Telegram formatting, except color formatting (since Telegram doesn't have colored text).

The exception to the "any" above is commands.

### Commands in chats

If the first two characters of a message are `![`, then the sequence is interpreted as a command. To avoid this and send a Telegram message that starts with `![`, write `!![`.

The current commands are:

Command                    | Description
---------------------------|-------------
`![silent]Message here`    | The message following the command will be send as a silent message, which means notifications for the message will not make a sound.
`![quiet]Message here`     | Same as `![silent]Message here`
`![recall]`                | Send the last 50 (by default, change in settings) messages from the chat again.
`![recall 25]`             | Send the last 25 (any number between 1 and 1000) messages from the chat again.
`![del 12345]`             | Delete the message with id `12345` for all users in the chat.
`![del_me 12345]`          | Delete the message with id `12345` only for yourself, while keeping it for other users.
`![reply 12345]Abc`        | Send the message as a reply to the message with id `12345`.
`![no_webpage_preview]Abc` | By default, Telegram generates a preview for the first link in a message. This disables that.

You may chain commands in the same message. For example, `![quiet]![reply 12345]![no_webpage_preview]https://www.youtube.com/watch?v=dQw4w9WgXcQ` will send a quiet reply to message `12345` without showing a preview for a link.

If the first two characters after a command are `![`, then another command is going to be interpreted. In this case, use the same rules as for the first command (`![silent]!![test]abc` will send the message `![test]abc` as a silent message).

## License

For now, TelegIRC is source-available, but not FOSS. I am still thinking of what license to choose.

Until I establish a general license, contact me if you actually like my source code so much that you want to use it. I'll be surprised and flattered.

---

[^1]: Very old IRC clients may use ANSI escape codes for formatting, and that's not supported.
