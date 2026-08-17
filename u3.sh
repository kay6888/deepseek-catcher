mkdir -p app/src/main/res/drawable

cat << 'EOF' > app/src/main/res/drawable/ic_whale_net.xml
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <!-- Deep Sea Background -->
    <path android:fillColor="#0B1D3A" android:pathData="M0,0 h108 v108 h-108 z" />
    <!-- Whale Body -->
    <path android:fillColor="#0077BE" android:pathData="M 15 65 C 15 45 40 35 60 45 C 75 52 85 45 95 35 C 95 65 75 80 50 80 C 25 80 15 75 15 65 Z" />
    <!-- Whale Tail -->
    <path android:fillColor="#005b94" android:pathData="M 90 40 C 98 30 105 40 95 50 C 105 60 98 70 90 60 Z" />
    <!-- Whale Eye -->
    <path android:fillColor="#FFFFFF" android:pathData="M 35 55 A 3 3 0 1 0 35 54.9 Z" />
    <!-- The Net -->
    <path android:strokeColor="#88FFFFFF" android:strokeWidth="1.5" android:pathData="M 20 40 L 80 80 M 30 35 L 90 75 M 40 30 L 95 65 M 20 75 L 80 35 M 30 80 L 90 40 M 40 85 L 95 50" />
</vector>
EOF

echo "Icon created successfully!"
