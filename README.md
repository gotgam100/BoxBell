# BoxBell

iOS용 복싱 라운드 타이머입니다. 실제 벨 사운드로 라운드 시작, 종료, 30초 전 알림을 알려주고, iOS 26 이상에서는 백그라운드 전환 시 남은 라운드 스케줄을 AlarmKit 알람으로 예약합니다.

## 기본 기능

- 2분, 3분 또는 직접 설정 라운드
- 30초 또는 60초 휴식 선택
- 기본 3라운드
- 1~12라운드 또는 무한 라운드 선택
- 붉은 벨 탭으로 시작 및 리셋
- 라운드 시작/종료/휴식 종료 시 벨 사운드 재생
- 라운드 30초 남았을 때 경고 벨 사운드 재생
- 한국어/영어 지원, 기본 언어는 한국어
- iOS 26 이상 AlarmKit 백그라운드 알람 지원

## 동작 방식

- 앱이 열려 있을 때는 앱 내부 타이머와 `AVAudioPlayer`로 벨을 재생합니다.
- 앱이 백그라운드로 전환되면 현재 남은 시간 기준으로 라운드/휴식 경계 알람을 미리 예약합니다.
- 앱으로 돌아오거나 리셋/새 시작 시에는 BoxBell이 저장한 알람 ID만 취소합니다.
- 일시정지 기능은 없습니다. 라운드 수와 휴식 시간은 타이머가 멈춘 상태에서만 변경할 수 있습니다.

## 열기

Xcode에서 `Boxbell.xcodeproj`를 열고 iPhone 시뮬레이터 또는 실제 기기로 실행하면 됩니다.

최소 지원 버전은 iOS 26입니다.

## 벨 소리 교체

현재 앱은 아래 사운드를 사용합니다.

- `Boxbell/Resources/bell_start_end.wav`: 라운드 시작/종료
- `Boxbell/Resources/bell_30_seconds.wav`: 라운드 30초 남았을 때

다른 소리를 쓰려면 같은 파일명으로 WAV 파일을 교체하세요.

권장 오디오:

- 포맷: WAV 또는 CAF
- 길이: 1~3초
- 샘플레이트: 44.1kHz
- 채널: mono 또는 stereo

## 이미지 사이즈 추천

앱 안에서 보이는 타임벨 이미지는 `Boxbell/Assets.xcassets/TimeBell.imageset/Bell_top.png`를 교체하면 됩니다.

추천:

- 앱 화면용: 1024 x 1024 px PNG, 투명 배경 가능
- 더 가벼운 화면용: 512 x 512 px PNG도 충분
- 앱 아이콘용: 1024 x 1024 px PNG, 투명 배경 없이 꽉 찬 정사각형

처음에는 1024 x 1024 원본 하나로 작업하고, Xcode asset catalog에 넣는 방식이 가장 편합니다.

## 정책 페이지

GitHub Pages용 문서는 `docs/` 폴더에 있습니다.

- 개인정보 처리방침: `docs/privacy.html`
- 이용약관: `docs/terms.html`
- 고객지원: `docs/support.html`
- 오픈소스 라이선스: `docs/licenses.html`
