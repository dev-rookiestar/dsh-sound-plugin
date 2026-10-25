window.__ModuleLoader__.load({
  id: "@dev-rookiestar/dsh-sound-plugin",
  factory(require) {
    const React = require("react");
    const h = React.createElement;
    const NS = "sound-plugin";

    function Switch({ checked, disabled, label, onChange }) {
      return h(
        "button",
        {
          type: "button",
          role: "switch",
          "aria-checked": checked,
          "aria-label": label,
          disabled,
          onClick: () => {
            if (!disabled) onChange(!checked);
          },
          style: {
            position: "relative",
            width: 36,
            height: 20,
            borderRadius: 999,
            border: "none",
            padding: 0,
            margin: 0,
            cursor: disabled ? "default" : "pointer",
            flexShrink: 0,
            background: checked
              ? "var(--dsw-alias-brand-primary)"
              : "var(--dsw-alias-state-idle-primary)",
            opacity: disabled ? 0.5 : 1,
            transition: "background 0.15s ease",
          },
        },
        h("span", {
          "aria-hidden": true,
          style: {
            position: "absolute",
            top: 2,
            left: checked ? 18 : 2,
            width: 16,
            height: 16,
            borderRadius: "50%",
            background: "var(--dsw-alias-bg-layer-1)",
            boxShadow: "0 1px 2px rgba(0, 0, 0, 0.25)",
            transition: "left 0.15s ease",
          },
        }),
      );
    }

    function ToggleRow({ field, useValue, setValue, t }) {
      const value = useValue((item) => item);
      const [busy, setBusy] = React.useState(false);
      const [failed, setFailed] = React.useState(false);
      const title = t(`${field}.title`);
      const description = t(`${field}.description`);

      return h(
        "div",
        {
          style: {
            borderBottom: ".5px solid var(--dsw-alias-border-l2)",
            justifyContent: "space-between",
            alignItems: "center",
            gap: 24,
            padding: "16px 0",
            display: "flex",
          },
        },
        h(
          "div",
          { style: { minWidth: 0 } },
          h(
            "div",
            {
              style: {
                fontSize: 14,
                lineHeight: "20px",
                color: "var(--dsw-alias-label-primary)",
              },
            },
            title,
          ),
          h(
            "div",
            {
              style: {
                color: "var(--dsw-alias-label-secondary)",
                marginTop: 4,
                fontSize: 12,
                lineHeight: "18px",
              },
            },
            description,
          ),
          failed &&
            h(
              "div",
              {
                role: "alert",
                style: {
                  color: "var(--dsw-alias-state-error-primary)",
                  marginTop: 4,
                  fontSize: 12,
                },
              },
              t("error"),
            ),
        ),
        h(Switch, {
          checked: value,
          disabled: busy,
          label: title,
          onChange: (next) => {
            setFailed(false);
            setBusy(true);
            Promise.resolve(setValue(next))
              .catch(() => setFailed(true))
              .finally(() => setBusy(false));
          },
        }),
      );
    }

    return {
      inject: ["slots", "locale", "configForms"],
      apply(ctx) {
        ctx.effect(
          () =>
            ctx.locale.register(NS, {
              zh: {
                "completion.title": "回复完成提示音",
                "completion.description": "AI 回复生成完成后播放系统提示音。",
                "approval.title": "待审批提醒",
                "approval.description": "出现待审批事项时播放系统提示音提醒。",
                error: "保存失败，请重试",
              },
              en: {
                "completion.title": "Completion sound",
                "completion.description":
                  "Play a system sound when the AI finishes responding.",
                "approval.title": "Approval reminder",
                "approval.description":
                  "Play a system sound when a pending approval appears.",
                error: "Could not save. Please try again.",
              },
            }),
          "completion-sound: dictionaries",
        );

        const form = ctx.configForms.get("sound-plugin");

        for (const [field, order] of [
          ["completion", 16],
          ["approval", 17],
        ]) {
          ctx.slots.inject(
            "settings.general.item",
            () =>
              ctx.slots.register(
                {
                  name: "settings.general.item",
                  id: `sound-plugin-${field}`,
                  order,
                  locale: NS,
                  inject: () => ({
                    field,
                    hooks: {
                      value: {
                        getSnapshot: () =>
                          form.getSnapshot().value?.[field] ?? true,
                        subscribe: (listener) => form.subscribe(listener),
                      },
                    },
                    setValue: (next) => form.set(field, next),
                  }),
                },
                ToggleRow,
              ),
          );
        }
      },
    };
  },
});
