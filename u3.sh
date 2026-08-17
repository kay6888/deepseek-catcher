cat << 'EOF' > app/src/main/res/values/strings.xml
<resources>
    <string name="app_name">DeepSeek Collector</string>
    <string name="accessibility_description">Monitors DeepSeek screen output and manages collected code.</string>
</resources>
EOF

git add app/src/main/res/values/strings.xml
git commit -m "Rename app to DeepSeek Collector"
git push
