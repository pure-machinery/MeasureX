cd font_generator/
odin build generate_font.odin -file -out:generate_font -o=speed;
echo 'Running generate_font.'
./generate_font;
cp -f asset asset.png -t ../assets;
rm -r asset asset.png;
cd ..;
echo 'Building binary.'
odin platform/linux_platform.odin -file -out:measure_x -o=speed;
strip measure_x;
du -sh measure_x;
