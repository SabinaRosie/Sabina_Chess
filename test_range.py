import requests

url = "https://manikadahal-sabina-chess.hf.space/api/media/videos/1/stream/video.mp4"
headers = {"Range": "bytes=0-100"}

r = requests.get(url, headers=headers)
print("Status Code:", r.status_code)
print("Response Headers:")
for k, v in r.headers.items():
    print(f"  {k}: {v}")
