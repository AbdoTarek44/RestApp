from pathlib import Path
import shutil
root=Path(__file__).resolve().parents[1]
manifest=Path('android/app/src/main/AndroidManifest.xml')
s=manifest.read_text(encoding='utf-8').replace('android:label="معلش تجربة"','android:label="معلش"')
assert 'android:label="معلش"' in s
manifest.write_text(s,encoding='utf-8')
res=Path('android/app/src/main/res')
shutil.copytree(root/'branding/android',res,dirs_exist_ok=True)
(res/'drawable/maalish_foreground.xml').write_bytes((root/'branding/maalish-foreground.xml').read_bytes())
(res/'values/maalish_colors.xml').write_text('<resources><color name="maalish_icon_background">#153047</color></resources>',encoding='utf-8')
for name in ['ic_launcher.xml','ic_launcher_round.xml']:
 p=res/'mipmap-anydpi-v26'/name;p.parent.mkdir(parents=True,exist_ok=True)
 p.write_text('<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@color/maalish_icon_background"/><foreground android:drawable="@drawable/maalish_foreground"/></adaptive-icon>',encoding='utf-8')
assets=Path('assets/branding');assets.mkdir(parents=True,exist_ok=True)
for name in ['increase-logo.png','maalish-icon.png']:shutil.copyfile(root/'branding'/name,assets/name)
p=Path('pubspec.yaml');s=p.read_text(encoding='utf-8').replace('  uses-material-design: true','  uses-material-design: true\n  assets:\n    - assets/branding/')
p.write_text(s,encoding='utf-8')
