# Page snapshot

```yaml
- generic [active] [ref=e1]:
  - navigation [ref=e2]:
    - link "대시보드" [ref=e3] [cursor=pointer]:
      - /url: /dashboard
    - link "매장 등록" [ref=e4] [cursor=pointer]:
      - /url: /stores/new
    - link "요금제" [ref=e5] [cursor=pointer]:
      - /url: /plans
    - link "반려동물" [ref=e6] [cursor=pointer]:
      - /url: /pets
    - link "캠페인" [ref=e7] [cursor=pointer]:
      - /url: /campaigns
    - link "캠페인 생성" [ref=e8] [cursor=pointer]:
      - /url: /campaigns/new
    - link "인보이스" [ref=e9] [cursor=pointer]:
      - /url: /billing/invoices
    - button "로그아웃" [ref=e10]
  - main [ref=e11]:
    - heading "요금제" [level=2] [ref=e12]
    - generic [ref=e13]:
      - text: "대상 매장:"
      - combobox [ref=e14]:
        - option "테스트매장" [selected]
    - generic [ref=e15]: "현재 구독: 미설정"
    - list
  - alert [ref=e16]
```