cd font_generator/
odin build generate_font.odin -file -out:generate_font.bin -o=speed;
echo 'Running generate_font.';
./generate_font.bin;
cp -f asset asset.png -t ../platform/assets;
rm -r asset asset.png;
cd ..;
echo 'Building release binary.';
echo $PWD;
odin platform/linux_platform.odin -file -out:measure_x.bin -o=speed;
strip measure_x.bin;
du -sh measure_x.bin;
