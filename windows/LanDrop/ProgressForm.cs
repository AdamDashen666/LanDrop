namespace LanDrop;

/// 屏幕左上角的小进度条：不抢焦点、不进任务栏；结束后显示“完成/失败”停 1 秒再用 1 秒淡出
sealed class ProgressForm : Form
{
    readonly Transfer t;
    readonly Label label = new() { Dock = DockStyle.Top, Height = 24, AutoEllipsis = true };
    readonly ProgressBar bar = new() { Dock = DockStyle.Bottom, Height = 14 };
    readonly System.Windows.Forms.Timer timer = new() { Interval = 100 };
    int doneTicks;

    public ProgressForm(Transfer t)
    {
        this.t = t;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        BackColor = SystemColors.Window;
        Padding = new Padding(10, 8, 10, 8);
        Size = new Size(340, 60);
        var area = Screen.PrimaryScreen!.WorkingArea;
        // 多个同时传输时往下叠
        Location = new Point(area.Left + 12, area.Top + 12 + Application.OpenForms.OfType<ProgressForm>().Count() * (Height + 8));
        bar.Style = t.Total > 0 ? ProgressBarStyle.Continuous : ProgressBarStyle.Marquee;
        Controls.Add(label);
        Controls.Add(bar);
        timer.Tick += (_, _) => Tick();
        timer.Start();
        Tick();
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var p = base.CreateParams;
            p.ExStyle |= 0x08000000 | 0x80; // WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW
            return p;
        }
    }

    void Tick()
    {
        if (t.Ok == null)
        {
            var mb = $"{t.Received / 1048576.0:0.0} MB";
            if (t.Total > 0)
            {
                var pct = (int)(t.Received * 100 / t.Total.Value);
                bar.Value = Math.Clamp(pct, 0, 100);
                label.Text = $"正在接收 {t.Name}  {pct}%  {mb}";
            }
            else label.Text = $"正在接收 {t.Name}  {mb}";
            return;
        }
        if (doneTicks++ == 0)
        {
            label.Text = (t.Ok == true ? "已完成  " : "失败  ") + t.Name;
            label.ForeColor = t.Ok == true ? SystemColors.ControlText : Color.Firebrick;
            bar.Style = ProgressBarStyle.Continuous;
            if (t.Ok == true) bar.Value = 100;
        }
        if (doneTicks > 10) Opacity = Math.Max(0, 1 - (doneTicks - 10) / 10.0);
        if (Opacity <= 0)
        {
            timer.Dispose();
            Close();
        }
    }
}
