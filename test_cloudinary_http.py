import requests

url = "http://res.cloudinary.com/dxkefvgpn/video/upload/w_848,h_480,c_scale,q_auto,fps_30,vc_h264:baseline:3.1,br_1m/v1779800616/hvftevrwmu4nh6necmfs.mp4"
r = requests.head(url)
print("Status Code:", r.status_code)
print("Headers:")
for k, v in r.headers.items():
    if "server-timing" in k.lower():
        print(f"  {k}: {v}")
