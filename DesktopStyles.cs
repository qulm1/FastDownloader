using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using System.Runtime.InteropServices;

namespace FastDownloader {
    internal static class Shape {
        public static GraphicsPath Rounded(Rectangle rect, int radius) {
            int d = Math.Max(2, Math.Min(radius * 2, Math.Min(rect.Width,rect.Height)-1));
            var path=new GraphicsPath();
            path.AddArc(rect.X,rect.Y,d,d,180,90); path.AddArc(rect.Right-d,rect.Y,d,d,270,90);
            path.AddArc(rect.Right-d,rect.Bottom-d,d,d,0,90); path.AddArc(rect.X,rect.Bottom-d,d,d,90,90);
            path.CloseFigure(); return path;
        }
        public static void Icon(Graphics g, string name, Rectangle bounds, Color color) {
            var saved=g.Save(); g.TranslateTransform(bounds.X,bounds.Y); g.ScaleTransform(bounds.Width/20f,bounds.Height/20f);
            using(var p=new Pen(color,1.5f)) {
                p.StartCap=LineCap.Round; p.EndCap=LineCap.Round; p.LineJoin=LineJoin.Round;
                switch(name) {
                    case "Plus": g.DrawLine(p,10,3,10,17); g.DrawLine(p,3,10,17,10); break;
                    case "Close": g.DrawLine(p,5,5,15,15); g.DrawLine(p,15,5,5,15); break;
                    case "Search": g.DrawEllipse(p,3,3,10,10); g.DrawLine(p,12,12,17,17); break;
                    case "All": g.DrawRectangles(p,new[]{new Rectangle(3,3,5,5),new Rectangle(12,3,5,5),new Rectangle(3,12,5,5),new Rectangle(12,12,5,5)}); break;
                    case "Completed": g.DrawEllipse(p,2,2,16,16); g.DrawLines(p,new[]{new Point(6,10),new Point(9,13),new Point(14,7)}); break;
                    case "Paused": g.DrawEllipse(p,2,2,16,16); g.DrawLine(p,8,7,8,13); g.DrawLine(p,12,7,12,13); break;
                    case "Incomplete": g.DrawEllipse(p,2,2,16,16); g.DrawLine(p,10,5,10,10); g.DrawLine(p,10,14,10,14.2f); break;
                    case "Resume": g.DrawPolygon(p,new[]{new Point(6,3),new Point(16,10),new Point(6,17)}); break;
                    case "Stop": g.DrawRectangle(p,4,4,12,12); break;
                    case "Folder": g.DrawLines(p,new[]{new Point(2,16),new Point(2,5),new Point(8,5),new Point(10,7),new Point(18,7),new Point(18,16),new Point(2,16)}); break;
                    case "Video": g.DrawRectangle(p,2,4,16,12); g.DrawPolygon(p,new[]{new Point(8,7),new Point(13,10),new Point(8,13)}); break;
                    case "Audio": g.DrawLines(p,new[]{new Point(8,14),new Point(8,5),new Point(16,3),new Point(16,12)}); g.DrawEllipse(p,3,12,5,4); g.DrawEllipse(p,11,10,5,4); break;
                    case "Image": g.DrawRectangle(p,2,3,16,14); g.DrawEllipse(p,5,6,3,3); g.DrawLines(p,new[]{new Point(3,16),new Point(9,10),new Point(13,14),new Point(16,11),new Point(18,13)}); break;
                    case "Archive": g.DrawRectangle(p,3,6,14,11); g.DrawRectangle(p,2,3,16,3); g.DrawLine(p,8,10,12,10); break;
                    case "Document": case "Other": g.DrawLines(p,new[]{new Point(5,2),new Point(12,2),new Point(16,6),new Point(16,18),new Point(5,18),new Point(5,2)}); g.DrawLines(p,new[]{new Point(12,2),new Point(12,6),new Point(16,6)}); g.DrawLine(p,8,10,13,10); g.DrawLine(p,8,13,13,13); break;
                    default: g.DrawLine(p,10,2,10,13); g.DrawLines(p,new[]{new Point(6,9),new Point(10,13),new Point(14,9)}); g.DrawLines(p,new[]{new Point(3,13),new Point(3,17),new Point(17,17),new Point(17,13)}); break;
                }
            }
            g.Restore(saved);
        }
    }
    public class SurfacePanel : Panel {
        public int Radius { get; set; }
        public Color BorderColor { get; set; }
        public SurfacePanel() { Radius=12; BorderColor=Color.FromArgb(225,229,236); DoubleBuffered=true; }
        protected override void OnPaintBackground(PaintEventArgs e) {
            e.Graphics.Clear(Parent==null ? BackColor : Parent.BackColor);
            e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
            using(var path=Shape.Rounded(new Rectangle(0,0,Width-1,Height-1),Radius)) {
                using(var b=new SolidBrush(BackColor))e.Graphics.FillPath(b,path);
                using(var p=new Pen(BorderColor))e.Graphics.DrawPath(p,path);
            }
        }
    }
    public class HintTextBox : TextBox {
        [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern IntPtr SendMessage(IntPtr h,int m,IntPtr w,string l);
        private string hint="";
        public string Hint { get {return hint;} set {hint=value; if(IsHandleCreated)SendMessage(Handle,0x1501,new IntPtr(1),hint);} }
        protected override void OnHandleCreated(EventArgs e){base.OnHandleCreated(e);SendMessage(Handle,0x1501,new IntPtr(1),hint);}
    }
    public class ModernButton : Button {
        public int Radius { get; set; }
        public string Glyph { get; set; }
        public string Badge { get; set; }
        public ModernButton() {
            Radius = 9;
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            UseVisualStyleBackColor = false;
            Cursor = Cursors.Hand;
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.Opaque, true);
        }
        protected override void OnPaintBackground(PaintEventArgs e) {
            e.Graphics.Clear(Parent == null ? SystemColors.Control : Parent.BackColor);
        }
        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); Invalidate(); }
        protected override void OnPaint(PaintEventArgs e) {
            // Owner-drawn buttons must repaint the entire rectangle, including the
            // pixels outside the rounded path. Otherwise native/focus pixels linger.
            e.Graphics.Clear(Parent == null ? SystemColors.Control : Parent.BackColor);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            var rect = new Rectangle(0, 0, Width - 1, Height - 1);
            int d = Math.Max(2, Math.Min(Radius * 2, Height - 1));
            using (var path = new GraphicsPath()) {
                path.AddArc(rect.X, rect.Y, d, d, 180, 90);
                path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
                path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
                path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
                path.CloseFigure();
                var color = Enabled ? BackColor : Color.FromArgb(234, 237, 242);
                if (Enabled && ClientRectangle.Contains(PointToClient(Cursor.Position))) color = ControlPaint.Light(color, 0.08f);
                using (var brush = new SolidBrush(color)) e.Graphics.FillPath(brush, path);
                if (Focused && ShowFocusCues) using (var pen = new Pen(Color.FromArgb(116,161,241))) {
                    using(var focus=Shape.Rounded(new Rectangle(2,2,Width-5,Height-5),Math.Max(2,Radius-2))) e.Graphics.DrawPath(pen,focus);
                }
            }
            Color ink=Enabled ? ForeColor : Color.FromArgb(166,173,185);
            int left=TextAlign==ContentAlignment.MiddleLeft ? 14 : Math.Max(10,(Width-TextRenderer.MeasureText(Text,Font).Width-(string.IsNullOrEmpty(Glyph)?0:27))/2);
            if(!string.IsNullOrEmpty(Glyph)) { Shape.Icon(e.Graphics,Glyph,new Rectangle(left,(Height-18)/2,18,18),ink); left+=29; }
            var label=new Rectangle(left,0,Math.Max(0,Width-left-(string.IsNullOrEmpty(Badge)?10:40)),Height);
            TextRenderer.DrawText(e.Graphics,Text,Font,label,ink,TextFormatFlags.Left|TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis|TextFormatFlags.NoPrefix);
            if(!string.IsNullOrEmpty(Badge)) TextRenderer.DrawText(e.Graphics,Badge,Font,new Rectangle(Width-40,0,28,Height),ink,TextFormatFlags.Right|TextFormatFlags.VerticalCenter);
        }
    }

    public class TaskGrid : DataGridView {
        public TaskGrid() { DoubleBuffered = true; }
        protected override void OnCellPainting(DataGridViewCellPaintingEventArgs e) {
            if(e.RowIndex>=0 && e.ColumnIndex>=0 && Columns[e.ColumnIndex].Name=="Name") {
                e.PaintBackground(e.ClipBounds,true);
                string name=Convert.ToString(e.FormattedValue);
                Shape.Icon(e.Graphics,"Document",new Rectangle(e.CellBounds.X+13,e.CellBounds.Y+23,20,20),Color.FromArgb(112,128,153));
                var label=new Rectangle(e.CellBounds.X+45,e.CellBounds.Y+12,Math.Max(10,e.CellBounds.Width-52),24);
                TextRenderer.DrawText(e.Graphics,name,e.CellStyle.Font,label,Color.FromArgb(34,43,61),TextFormatFlags.Left|TextFormatFlags.EndEllipsis);
                string folder=Convert.ToString(Rows[e.RowIndex].Cells["Folder"].Value);
                using(var font=new Font(e.CellStyle.Font.FontFamily,8.5f))
                    TextRenderer.DrawText(e.Graphics,folder,font,new Rectangle(label.X,e.CellBounds.Y+37,label.Width,20),Color.FromArgb(143,151,166),TextFormatFlags.Left|TextFormatFlags.EndEllipsis);
                e.Handled=true;return;
            }
            if(e.RowIndex>=0 && e.ColumnIndex>=0 && Columns[e.ColumnIndex].Name=="Status") {
                e.PaintBackground(e.ClipBounds,true);
                string state=Convert.ToString(e.FormattedValue);
                Color bg=Color.FromArgb(241,243,247),fg=Color.FromArgb(119,129,146);
                if(state=="下载中"||state=="正在连接"||state=="排队中"){bg=Color.FromArgb(235,242,255);fg=Color.FromArgb(45,113,231);}
                if(state=="已完成"){bg=Color.FromArgb(232,247,240);fg=Color.FromArgb(39,142,102);}
                if(state.StartsWith("失败")){bg=Color.FromArgb(255,239,237);fg=Color.FromArgb(190,72,65);}
                var pill=new Rectangle(e.CellBounds.X+6,e.CellBounds.Y+21,Math.Min(e.CellBounds.Width-12,98),27);
                e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
                using(var path=Shape.Rounded(pill,7))using(var b=new SolidBrush(bg))e.Graphics.FillPath(b,path);
                using(var f=new Font(e.CellStyle.Font.FontFamily,8.5f))TextRenderer.DrawText(e.Graphics,state,f,pill,fg,TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis);
                e.Handled=true;return;
            }
            if (e.RowIndex >= 0 && e.ColumnIndex >= 0 && Columns[e.ColumnIndex].Name == "Progress") {
                e.PaintBackground(e.ClipBounds, true);
                string text = Convert.ToString(e.FormattedValue);
                int percent;
                var bar = new Rectangle(e.CellBounds.X + 10, e.CellBounds.Y + 45, Math.Max(10, e.CellBounds.Width - 22), 3);
                using (var brush = new SolidBrush(Color.FromArgb(229, 235, 245))) e.Graphics.FillRectangle(brush,bar);
                if (int.TryParse(text.TrimEnd('%'), out percent)) {
                    percent = Math.Max(0,Math.Min(100,percent));
                    using (var brush = new SolidBrush(Color.FromArgb(52, 120, 246))) e.Graphics.FillRectangle(brush,bar.X,bar.Y,bar.Width*percent/100,bar.Height);
                }
                var label = new Rectangle(e.CellBounds.X+10,e.CellBounds.Y+17,e.CellBounds.Width-18,22);
                TextRenderer.DrawText(e.Graphics,text,e.CellStyle.Font,label,Color.FromArgb(73,84,105),TextFormatFlags.Left|TextFormatFlags.EndEllipsis);
                e.Handled=true;
                return;
            }
            base.OnCellPainting(e);
        }
    }
}
