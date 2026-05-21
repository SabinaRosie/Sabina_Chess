import requests

def test_api():
    domain = "sabina-chess.metered.live"
    
    # Base key with placeholders
    # Index 5: {char1}
    # Index 7: {char2}
    # Index 43: {char3}
    base_key_template = "X45gf{char1}P{char2}gqP3S-QuG46j4TV4tuMd26qsxT_NXWoEhaN{char3}pSTU"
    
    options = ['I', 'l', '1']
    
    found = False
    for c1 in options:
        for c2 in options:
            for c3 in options:
                key = base_key_template.format(char1=c1, char2=c2, char3=c3)
                url = f"https://{domain}/api/v1/turn/credential?secretKey={key}"
                try:
                    resp = requests.post(url, json={"label": "sabina-chess-session"}, timeout=5)
                    if resp.status_code == 200:
                        print(f"🎉 SUCCESS! Working Key: {key}")
                        print(f"Response: {resp.text}")
                        found = True
                        break
                    else:
                        # Print only if it's NOT a 401 or has a different error
                        if "invalid secretKey" not in resp.text:
                            print(f"Key: {key} -> Code: {resp.status_code}, Response: {resp.text}")
                except Exception as e:
                    pass
            if found:
                break
        if found:
            break
            
    if not found:
        print("❌ All 27 standard combinations failed.")

if __name__ == '__main__':
    test_api()
