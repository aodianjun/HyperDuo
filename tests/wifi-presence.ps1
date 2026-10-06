# Proves WifiPresence.resolve()'s decision rule: a live framework answer always
# wins over the module's own two witnesses, and only when the framework has not
# spoken yet do the icon and the cached level get a say.
#
# The rule is extracted from the production source rather than copied, so this
# fails the moment the shipped rule and the tested rule drift apart - the same
# shape the five workbenches under work\ use.
#
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File tests\wifi-presence.ps1
#
# ASCII only on purpose: PowerShell 5.1 reads BOM-less files as ANSI, so a script
# without a BOM must not contain non-ASCII bytes.
$ErrorActionPreference = 'Stop'

$Root = Split-Path $PSScriptRoot -Parent
# The repo vendors its own JDK and does not put it on PATH - see build.ps1.
$Jdk = Join-Path $Root '.tools\jdk\jdk-21.0.12.1+1\bin'
$Javac = Join-Path $Jdk 'javac.exe'
$Java = Join-Path $Jdk 'java.exe'
if (-not (Test-Path $Javac)) { throw "javac not found: $Javac" }

$s = Get-Content (Join-Path $Root 'app\src\main\java\io\github\yixing233\hyperduo\WifiPresence.java') -Raw
$m = [regex]::Match($s, '(?s)static boolean resolve\(boolean iconVisible, int cachedLevel\) \{.*?\n    \}').Value
if (-not $m) { throw 'Production resolver missing' }

$out = Join-Path $Root 'work\issue13\tests'
New-Item -ItemType Directory -Force -Path $out | Out-Null

$test = @"
public class WifiTest {
 static Boolean connected;
 $m
 public static void main(String[] args){
  int count=0;
  for(Boolean live:new Boolean[]{null,false,true})for(boolean icon:new boolean[]{false,true})for(int level:new int[]{-1,0,4}){
   connected=live;boolean want=live==null?(icon||level>=0):live;
   if(resolve(icon,level)!=want)throw new AssertionError("stale icon overrides live state");count++;
  }
  connected=false;if(resolve(true,4))throw new AssertionError("disabled wifi stale cache");
  connected=true;if(!resolve(false,-1))throw new AssertionError("reconnected wifi");
  connected=false;if(resolve(true,4))throw new AssertionError("disconnected again");
  System.out.println("PASS: "+count+" live/icon/cache cases and 3 reconnect transitions");
 }
}
"@

# UTF8Encoding($false) - a BOM makes javac reject the first token, and
# -Encoding utf8NoBOM only exists in PowerShell 7.
$src = Join-Path $out 'WifiTest.java'
[System.IO.File]::WriteAllText($src, $test, (New-Object System.Text.UTF8Encoding($false)))

& $Javac -d $out $src
if ($LASTEXITCODE) { throw "Compilation failed ($LASTEXITCODE)" }
& $Java -Xmx64m -cp $out WifiTest
if ($LASTEXITCODE) { throw "Test failed ($LASTEXITCODE)" }
