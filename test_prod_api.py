import requests

url = "https://manikadahal-sabina-chess.hf.space/api/media/videos/"
try:
    r = requests.get(url, timeout=10)
    print("Status Code:", r.status_code)
    if r.status_code == 200:
        videos = r.json()
        for v in videos:
            print(f"ID: {v['id']}, Title: {v['title']}")
            print(f"  video_url: {v['video_url']}")
            print(f"  stream_url: {v['stream_url']}")
    else:
        print("Response:", r.text[:500])
except Exception as e:
    print("Error:", e)
