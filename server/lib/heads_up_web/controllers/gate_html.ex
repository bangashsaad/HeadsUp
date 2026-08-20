defmodule HeadsUpWeb.GateHTML do
  use HeadsUpWeb, :html

  # Saad's App Gate design, verbatim: the ghost VS, the purple glow, the big
  # italic headline, one lime CTA, the real-slate ticker, and the escape
  # hatch that opens the SURE ABOUT THAT? sheet instead of just leaving.
  def show(assigns) do
    ~H"""
    <div
      id="gate"
      data-tf={@testflight_url || ""}
      style="min-height:100dvh;box-sizing:border-box;display:flex;flex-direction:column;background:radial-gradient(500px 340px at 50% -8%,rgba(124,92,255,.22),transparent 65%),#07080C;color:#F4F5F7;overflow:hidden;position:relative"
      class="hu-body"
    >
      <span style="position:absolute;right:-30px;top:120px;font-family:'Archivo Black',sans-serif;font-style:italic;font-size:190px;color:transparent;-webkit-text-stroke:1px rgba(244,245,247,.06);pointer-events:none;line-height:1">
        VS
      </span>

      <div style="padding:34px 26px 0;display:flex;flex-direction:column;align-items:flex-start;position:relative">
        <span class="hu-black" style="font-size:27px;letter-spacing:-.5px;line-height:1">
          <span style="color:#F4F5F7">HEADS</span><span style="color:#C8FF2E">UP</span>
        </span>
        <span style="font-size:9px;font-weight:800;letter-spacing:3.5px;color:#565D73;margin-top:4px">FANTASY DUELS</span>
      </div>

      <div style="flex:1;display:flex;flex-direction:column;justify-content:center;padding:20px 26px;position:relative">
        <span
          :if={@testflight_url}
          style="display:inline-flex;align-items:center;gap:7px;align-self:flex-start;background:#12141D;border:1px solid #252A3A;border-radius:999px;padding:5px 12px"
        >
          <span class="huw-blink" style="width:5px;height:5px;border-radius:3px;background:#FF4557"></span>
          <span style="font-size:10px;font-weight:800;letter-spacing:1.5px;color:#8B91A7">DUELS ARE LIVE</span>
        </span>
        <span
          :if={!@testflight_url}
          style="display:inline-flex;align-items:center;gap:7px;align-self:flex-start;background:rgba(124,92,255,.12);border:1px solid #7C5CFF;border-radius:999px;padding:5px 12px"
        >
          <span class="huw-blink" style="width:5px;height:5px;border-radius:3px;background:#9F8BFF"></span>
          <span style="font-size:10px;font-weight:800;letter-spacing:1.5px;color:#9F8BFF">BETA · INVITE ONLY</span>
        </span>

        <h1 class="hu-black" style="font-size:44px;line-height:.98;letter-spacing:-1px;color:#F4F5F7;margin:16px 0 0">
          YOUR RIVALS<br />ARE IN THE APP<span style="color:#C8FF2E">.</span>
        </h1>

        <p :if={@testflight_url} style="font-size:14.5px;line-height:1.6;color:#8B91A7;margin:14px 0 0;max-width:300px">
          Drafts on a clock, live scores, trash talk the second it lands — the duel lives in your pocket. The web version is built for the big screen.
        </p>
        <p :if={!@testflight_url} style="font-size:14.5px;line-height:1.6;color:#8B91A7;margin:14px 0 0;max-width:300px">
          The beta is invite-only for now. Got called out by a friend? Their invite is your way in.
        </p>

        <a
          id="open-app"
          href={@testflight_url || "headsup://"}
          class="hu-cond"
          style={"margin-top:26px;background:#C8FF2E;color:#0A0B10;text-decoration:none;display:block;border-radius:999px;padding:16px 0;width:100%;text-align:center;font-size:20px;letter-spacing:.5px;cursor:pointer#{if @testflight_url, do: ";animation:huw-pulse 2.4s infinite"}"}
        >
          {if @testflight_url, do: "OPEN THE APP →", else: "I ALREADY HAVE IT — OPEN THE APP →"}
        </a>

        <span :if={@testflight_url} style="font-size:11px;font-weight:700;color:#565D73;margin-top:12px;align-self:center">
          Not installed? Same button lands on TestFlight.
        </span>
        <span
          :if={!@testflight_url}
          id="open-miss"
          style="display:none;font-size:11px;font-weight:700;color:#FFB021;margin-top:12px;align-self:center;text-align:center"
        >
          Didn't open? Then it's not on this phone yet — you'll need that invite.
        </span>
        <span
          :if={!@testflight_url}
          style="font-size:11px;font-weight:700;color:#565D73;margin-top:12px;align-self:center;text-align:center;line-height:1.6"
        >
          No invite yet? Duel someone who's in —<br />winners hand them out.
        </span>

        <span style="font-size:10px;font-weight:800;letter-spacing:1.5px;color:#565D73;margin-top:18px;align-self:center;border:1px solid #1A1E2B;border-radius:999px;padding:6px 14px;white-space:nowrap">
          🤖 ANDROID — COMING SOON
        </span>
      </div>

      <div :if={@ticker != []} style="border-top:1px solid #1A1E2B;background:#0D0F16;padding:9px 0;overflow:hidden;white-space:nowrap">
        <div style="display:inline-flex;animation:huw-marq 22s linear infinite">
          <span :for={t <- @ticker ++ @ticker} style="display:inline-flex;align-items:center;gap:8px;margin-right:26px">
            <span class="hu-cond" style={"font-weight:700;font-size:14px;font-style:normal;color:#{t.tag_color}"}>{t.tag}</span>
            <span class="hu-cond" style="font-weight:700;font-size:14px;font-style:normal;color:#F4F5F7">{t.line}</span>
          </span>
        </div>
      </div>

      <div style="padding:14px 0 18px;text-align:center;background:#0D0F16">
        <a
          id="escape-link"
          href="/get-the-app/continue"
          style="background:transparent;border:none;font-size:11px;font-weight:600;color:#3A4157;text-decoration:underline;text-underline-offset:3px;cursor:pointer"
        >
          continue to the web version anyway
        </a>
      </div>

      <%!-- SURE ABOUT THAT? — the escape-hatch sheet, hidden until the ghost link --%>
      <div id="escape-sheet" style="display:none;position:fixed;inset:0;z-index:50;flex-direction:column;justify-content:flex-end">
        <div style="position:absolute;inset:0;background:rgba(7,8,12,.55)"></div>
        <div style="position:relative;background:#12141D;border-top:1px solid #252A3A;border-radius:22px 22px 0 0;padding:24px 26px 30px;display:flex;flex-direction:column">
          <span style="width:36px;height:4px;border-radius:2px;background:#252A3A;align-self:center;margin-bottom:18px"></span>
          <span class="hu-cond" style="font-size:24px;letter-spacing:.5px;color:#F4F5F7">SURE ABOUT THAT?</span>
          <p style="font-size:13px;line-height:1.6;color:#8B91A7;margin:8px 0 0">
            The web version isn't built for phones — drafting on a 390px grid is choosing hard mode. It'll work, it just won't be pretty.
          </p>
          <button
            id="return-safety"
            class="hu-cond"
            style="margin-top:18px;background:#C8FF2E;color:#0A0B10;border:none;border-radius:999px;padding:14px 0;text-align:center;font-size:17px;letter-spacing:.5px;cursor:pointer"
          >
            RETURN TO SAFETY →
          </button>
          <a
            href="/get-the-app/continue"
            class="hu-cond"
            style="margin-top:10px;border:1px solid #252A3A;color:#8B91A7;border-radius:999px;padding:13px 0;text-align:center;font-size:15px;letter-spacing:.5px;cursor:pointer;text-decoration:none"
          >
            CONTINUE TO WEB — HARD MODE
          </a>
          <span style="font-size:10px;font-weight:600;color:#3A4157;margin-top:12px;align-self:center">
            We won't ask again on this device.
          </span>
        </div>
      </div>
    </div>

    <script>
      (() => {
        const tf = document.getElementById("gate").dataset.tf;
        const miss = document.getElementById("open-miss");

        document.getElementById("escape-link").addEventListener("click", (ev) => {
          ev.preventDefault();
          document.getElementById("escape-sheet").style.display = "flex";
        });

        document.getElementById("open-app").addEventListener("click", (ev) => {
          ev.preventDefault();
          const t = setTimeout(() => {
            if (document.hidden) return;
            if (tf) {
              location.href = tf;
            } else if (miss) {
              miss.style.display = "block";
            }
          }, 800);
          addEventListener("pagehide", () => clearTimeout(t), { once: true });
          location.href = "headsup://";
        });

        const sheet = document.getElementById("escape-sheet");
        document.getElementById("return-safety").addEventListener("click", () => (sheet.style.display = "none"));
      })();
    </script>
    """
  end
end
