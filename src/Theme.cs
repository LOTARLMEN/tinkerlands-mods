using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Windows.Forms;

namespace TinkerlandsMods {
    internal static class Theme {
        public static readonly Color Background = Color.FromArgb(25, 19, 38);
        public static readonly Color Shadow = Color.FromArgb(17, 12, 28);
        public static readonly Color Panel = Color.FromArgb(37, 27, 55);
        public static readonly Color Raised = Color.FromArgb(49, 36, 72);
        public static readonly Color Border = Color.FromArgb(86, 63, 114);
        public static readonly Color Paper = Color.FromArgb(250, 232, 205);
        public static readonly Color Text = Color.FromArgb(230, 218, 239);
        public static readonly Color Muted = Color.FromArgb(179, 167, 193);
        public static readonly Color Installed = Color.FromArgb(190, 182, 198);
        public static readonly Color Gold = Color.FromArgb(248, 190, 104);
        public static readonly Color Mint = Color.FromArgb(154, 217, 181);
        public static readonly Color Error = Color.FromArgb(251, 155, 155);

        public static readonly Font Body = new Font("Segoe UI", 10f);
        public static readonly Font Small = new Font("Segoe UI", 9f);
        public static readonly Font Button = new Font("Segoe UI", 9.5f, FontStyle.Bold);
        public static readonly Font Heading = new Font("Segoe UI", 13f, FontStyle.Bold);
        public static readonly Font DetailTitle = new Font("Segoe UI", 17f, FontStyle.Bold);

        internal static void Fill(Graphics g, Color color, Rectangle bounds) {
            using (var brush = new SolidBrush(color)) g.FillRectangle(brush, bounds);
        }

        internal static void Frame(Graphics g, Rectangle bounds, Color fill, Color edge, int depth) {
            if (bounds.Width < 8 || bounds.Height < 8) return;
            Fill(g, Shadow, bounds);
            Fill(g, edge, new Rectangle(bounds.X + 2, bounds.Y, bounds.Width - 4, bounds.Height - depth));
            Fill(g, edge, new Rectangle(bounds.X, bounds.Y + 2, bounds.Width, bounds.Height - depth - 4));
            Fill(g, fill, new Rectangle(bounds.X + 2, bounds.Y + 2, bounds.Width - 4, bounds.Height - depth - 4));
        }

        internal static Label Label(string caption, Font font, Color color) {
            return new Label { Text = caption, Font = font, ForeColor = color, BackColor = Color.Transparent,
                TextAlign = ContentAlignment.MiddleLeft, UseMnemonic = false, AutoEllipsis = true, Margin = Padding.Empty };
        }
    }

    internal sealed class ScrollColumn : Panel {
        readonly Panel viewport = new Panel();
        readonly VScrollBar scrollbar = new VScrollBar { Visible = false, SmallChange = 19 };
        int scrollLimit, contentWidth;

        public ScrollColumn() {
            DoubleBuffered = true;
            Controls.Add(viewport); Controls.Add(scrollbar);
            ClientSizeChanged += (s, e) => Arrange();
            scrollbar.ValueChanged += (s, e) => PlaceItems();
        }

        public ControlCollection Items { get { return viewport.Controls; } }
        public int Offset {
            get { return scrollbar.Value; }
            set { scrollbar.Value = Math.Max(0, Math.Min(scrollLimit, value)); }
        }

        public void Arrange() {
            if (Width <= Padding.Horizontal || Height == 0) return;
            int rail = SystemInformation.VerticalScrollBarWidth;
            contentWidth = Width - Padding.Horizontal;
            int total = Items.Cast<Control>().Sum(item => Measure(item, contentWidth)) + Padding.Vertical;
            bool overflow = total > Height;
            int viewportWidth = overflow ? Width - rail : Width;
            viewport.SetBounds(0, 0, viewportWidth, Height);
            if (overflow) {
                contentWidth = Math.Max(1, contentWidth - rail);
                total = Items.Cast<Control>().Sum(item => Measure(item, contentWidth)) + Padding.Vertical;
            }
            scrollLimit = Math.Max(0, total - Height);
            scrollbar.SetBounds(viewportWidth, 0, rail, Height);
            scrollbar.Maximum = Math.Max(0, total - 1);
            scrollbar.LargeChange = Height;
            scrollbar.Visible = overflow;
            Offset = Offset;
            PlaceItems();
        }

        void PlaceItems() {
            int top = Padding.Top - Offset;
            foreach (Control item in Items) {
                int height = Measure(item, contentWidth);
                item.SetBounds(Padding.Left, top, contentWidth, height - item.Margin.Bottom);
                top += height;
            }
        }

        public void Reveal(Control item) {
            if (item.Top < 0) Offset += item.Top - Padding.Top;
            else if (item.Bottom > Height) Offset += item.Bottom - Height + Padding.Bottom;
        }

        static int Measure(Control item, int width) {
            var label = item as Label;
            int height = label == null ? item.Height : TextRenderer.MeasureText(label.Text, label.Font,
                new Size(width, Int32.MaxValue), TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix | TextFormatFlags.TextBoxControl).Height;
            return height + item.Margin.Bottom;
        }

        public void Wheel(int delta) {
            if (!scrollbar.Visible) return;
            int lines = SystemInformation.MouseWheelScrollLines;
            int step = lines < 0 ? ClientSize.Height : lines * 19;
            Offset -= delta * step / 120;
        }
    }

    internal sealed class GameButton : Button {
        readonly bool primary;
        readonly bool quiet;
        bool hover, pressed;

        public GameButton(string caption, bool primary = false, bool quiet = false) {
            this.primary = primary; this.quiet = quiet;
            Text = caption; Font = Theme.Button; FlatStyle = FlatStyle.Flat;
            UseMnemonic = false; Cursor = Cursors.Hand; ForeColor = Theme.Paper;
            SetStyle(ControlStyles.OptimizedDoubleBuffer, true);
        }

        protected override void OnPaint(PaintEventArgs e) {
            Color fill = Theme.Raised, edge = Theme.Border, ink = ForeColor;
            if (primary) {
                fill = pressed ? Color.FromArgb(221, 153, 76) : hover ? Color.FromArgb(255, 209, 137) : Theme.Gold;
                edge = Color.FromArgb(255, 224, 171); ink = Theme.Shadow;
            } else if (hover) fill = Color.FromArgb(68, 49, 96);
            if (!Enabled) { fill = Theme.Panel; edge = Theme.Raised; ink = Theme.Muted; }
            if (quiet) {
                if (!hover || !Enabled) fill = BackColor;
                // The opaque button owns every pixel of its reusable paint buffer.
                Theme.Fill(e.Graphics, fill, ClientRectangle);
            } else Theme.Frame(e.Graphics, ClientRectangle, fill, edge, pressed ? 1 : 3);
            var textBounds = Rectangle.Inflate(ClientRectangle, -7, 0);
            var flags = TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis |
                TextFormatFlags.NoPrefix | TextFormatFlags.PreserveGraphicsClipping;
            if (TextAlign == ContentAlignment.MiddleCenter) flags |= TextFormatFlags.HorizontalCenter;
            TextRenderer.DrawText(e.Graphics, Text, Font, textBounds, ink, flags);
            if (Focused && ShowFocusCues) ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(ClientRectangle, -4, -4), ink, fill);
        }

        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); hover = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); hover = pressed = false; Invalidate(); }
        protected override void OnMouseDown(MouseEventArgs e) { base.OnMouseDown(e); pressed = e.Button == MouseButtons.Left; Invalidate(); }
        protected override void OnMouseUp(MouseEventArgs e) { base.OnMouseUp(e); pressed = false; Invalidate(); }
    }

    internal sealed class GameBanner : Panel {
        readonly Label title = Theme.Label("TINKERLANDS", new Font("Segoe UI Black", 26f, FontStyle.Bold), Theme.Paper);
        readonly Label caption = Theme.Label("Установщик модов", Theme.Heading, Theme.Gold);

        public GameBanner() {
            DoubleBuffered = true; BackColor = Theme.Panel;
            title.SetBounds(24, 11, 440, 45); caption.SetBounds(27, 55, 350, 28);
            Controls.Add(title); Controls.Add(caption);
        }

        protected override void OnPaintBackground(PaintEventArgs e) {
            Theme.Frame(e.Graphics, ClientRectangle, Theme.Panel, Theme.Border, 4);
            if (Width < 480 || Height < 36) return;
            var graphics = e.Graphics;
            GraphicsState state = graphics.Save();
            graphics.SetClip(new Rectangle(2, 2, Width - 4, Height - 8));
            graphics.TranslateTransform(Width - 396, 4);
            graphics.ScaleTransform(3f, 3f);
            DrawCoast(graphics);
            graphics.Restore(state);
        }

        static void DrawCoast(Graphics g) {
            Color sky = Color.FromArgb(71, 46, 94);
            Theme.Fill(g, sky, new Rectangle(8, 0, 124, 22));
            Theme.Fill(g, Color.FromArgb(97, 58, 104), new Rectangle(0, 9, 132, 14));
            Theme.Fill(g, Color.FromArgb(140, 78, 110), new Rectangle(19, 15, 113, 8));
            Color sun = Color.FromArgb(248, 180, 108);
            Theme.Fill(g, sun, new Rectangle(101, 5, 10, 17));
            Theme.Fill(g, sun, new Rectangle(98, 8, 16, 14));
            Theme.Fill(g, Color.FromArgb(217, 122, 102), new Rectangle(92, 17, 27, 2));
            Theme.Fill(g, Color.FromArgb(186, 101, 112), new Rectangle(60, 10, 12, 2));
            Theme.Fill(g, Color.FromArgb(186, 101, 112), new Rectangle(67, 12, 11, 1));
            Theme.Fill(g, Color.FromArgb(43, 49, 105), new Rectangle(6, 22, 126, 10));
            Theme.Fill(g, Color.FromArgb(55, 81, 129), new Rectangle(24, 23, 92, 2));
            Theme.Fill(g, Color.FromArgb(95, 126, 156), new Rectangle(60, 24, 21, 1));
            Theme.Fill(g, Color.FromArgb(95, 126, 156), new Rectangle(84, 23, 11, 1));
            Theme.Fill(g, Color.FromArgb(55, 81, 129), new Rectangle(42, 28, 31, 1));
            Theme.Fill(g, Color.FromArgb(55, 81, 129), new Rectangle(28, 26, 11, 1));
            Color shoreline = Color.FromArgb(197, 131, 107);
            Theme.Fill(g, shoreline, new Rectangle(92, 28, 40, 5));
            Theme.Fill(g, shoreline, new Rectangle(106, 25, 26, 5));
            Color land = Color.FromArgb(43, 38, 69);
            Theme.Fill(g, land, new Rectangle(99, 29, 33, 4));
            Theme.Fill(g, land, new Rectangle(113, 26, 19, 5));
            Theme.Fill(g, land, new Rectangle(121, 20, 11, 8));
            Theme.Fill(g, land, new Rectangle(124, 16, 8, 7));
            Color leaves = Color.FromArgb(36, 45, 63);
            Theme.Fill(g, leaves, new Rectangle(119, 8, 2, 17));
            Theme.Fill(g, leaves, new Rectangle(115, 7, 11, 2));
            Theme.Fill(g, leaves, new Rectangle(112, 9, 5, 2));
            Theme.Fill(g, leaves, new Rectangle(124, 9, 5, 2));
            Theme.Fill(g, leaves, new Rectangle(127, 11, 3, 2));
        }
    }
}
