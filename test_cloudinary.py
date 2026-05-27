import requests

url = "https://res.cloudinary.com/dxkefvgpn/video/upload/w_854,h_480,c_limit,q_auto,vc_h264:baseline:3.0,br_1m/v1779450547/mw0zucb3h9j8rg6polgw.mp4"
r = requests.head(url)
print("Status Code:", r.status_code)
print("Headers:")
for k, v in r.headers.items():
    print(f"  {k}: {v}")
