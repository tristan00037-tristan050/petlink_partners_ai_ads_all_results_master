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
    - heading "로그인" [level=2] [ref=e12]
    - generic [ref=e13]:
      - textbox "이메일" [ref=e14]
      - textbox "비밀번호" [ref=e15]
      - button "로그인" [ref=e16] [cursor=pointer]
    - paragraph [ref=e17]:
      - text: 계정이 없으신가요?
      - link "회원가입" [ref=e18] [cursor=pointer]:
        - /url: /signup
  - alert [ref=e19]
```