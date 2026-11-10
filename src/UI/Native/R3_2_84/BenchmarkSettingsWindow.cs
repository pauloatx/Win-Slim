using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Shell;
using System.Windows.Threading;
using System.Windows.Automation;
using System.Text.RegularExpressions;

namespace WinSlim.NativeUI
{
    internal sealed class BenchmarkSettingsSession : IDisposable
    {
        private readonly BenchmarkOverlay _overlay;
        private readonly BenchmarkHotkeys _hotkeys;
        private readonly BenchmarkOverlayPlacement _opening;
        private readonly bool _wasSuspended;
        private readonly Action<string> _capture;
        private bool _saved, _disposed;
        private bool _themeSyncing;
        private BenchmarkOverlay _live;
        private BenchmarkOverlayPlacement _liveOpening;
        internal BenchmarkOverlayPlacement Opening {get{return _opening.Clone();}}
        internal void SetFocused(bool focused){if(_hotkeys!=null)_hotkeys.Suspended=focused||_wasSuspended;}
        internal BenchmarkSettingsSession(BenchmarkOverlay overlay,BenchmarkHotkeys hotkeys)
        {
            _overlay=overlay;_hotkeys=hotkeys;_opening=overlay.BeginPreferencesEdit();
            overlay.ThemePreferenceChanged+=SynchronizeTheme;
            if(hotkeys!=null){_wasSuspended=hotkeys.Suspended;_capture=hotkeys.Capture;hotkeys.Suspended=true;}
        }
        internal void Attach(BenchmarkOverlay live)
        {
            if(live==_overlay||live==_live||live.GameIdentity!=_overlay.GameIdentity)return;
            if(_live!=null){_live.ThemePreferenceChanged-=SynchronizeTheme;_live.CancelPreferencesEdit(_liveOpening);}
            _live=live;_liveOpening=live.BeginPreferencesEdit();_live.Preferences.CopyAppearance(_overlay.Preferences);_live.ApplyEditedPreferences();
            _live.ThemePreferenceChanged+=SynchronizeTheme;
        }
        private void SynchronizeTheme(BenchmarkOverlay source)
        {
            if(_themeSyncing||_disposed)return;_themeSyncing=true;
            try{if(source!=_overlay){_overlay.Preferences.ThemeMode=source.ThemeMode;_overlay.RefreshSystemTheme();}if(_live!=null&&source!=_live){_live.Preferences.ThemeMode=source.ThemeMode;_live.RefreshSystemTheme();}}
            finally{_themeSyncing=false;}
        }
        internal void Apply(Action<BenchmarkOverlayPlacement> edit){edit(_overlay.Preferences);_overlay.ApplyEditedPreferences();if(_live!=null){_live.Preferences.CopyAppearance(_overlay.Preferences);_live.ApplyEditedPreferences();}}
        internal void Save(string[] bindings)
        {
            string[] old=_hotkeys==null?null:_hotkeys.Bindings;
            if(_hotkeys!=null){_hotkeys.Apply(bindings,false);if(_overlay.General)_hotkeys.Apply(old,false);}
            try{
                if(_live!=null){var appearance=_overlay.Preferences.Clone();_overlay.Preferences.CopyFrom(_live.Preferences);_overlay.Preferences.CopyAppearance(appearance);}
                _overlay.Preferences.Hotkeys=(string[])bindings.Clone();_overlay.CommitPreferencesEdit();
                if(_live!=null){_live.Preferences.Hotkeys=(string[])bindings.Clone();_live.CommitPreferencesEdit(false);}
                _saved=true;
            }
            catch{if(_hotkeys!=null)_hotkeys.Apply(old,false);throw;}
        }
        public void Dispose()
        {
            if(_disposed)return;_disposed=true;
            _overlay.ThemePreferenceChanged-=SynchronizeTheme;if(_live!=null)_live.ThemePreferenceChanged-=SynchronizeTheme;
            try{if(!_saved){_overlay.CancelPreferencesEdit(_opening);if(_live!=null)_live.CancelPreferencesEdit(_liveOpening);}}
            finally{if(_hotkeys!=null){_hotkeys.Capture=_capture;_hotkeys.Suspended=_wasSuspended;}}
        }
    }

    internal sealed class BenchmarkSettingsWindow : Window
    {
        private readonly BenchmarkOverlay _overlay,_preview;
        private readonly BenchmarkHotkeys _hotkeys;
        private readonly BenchmarkSettingsSession _session;
        private readonly Button[] _keys=new Button[3];
        private readonly TextBlock[] _errors=new TextBlock[3];
        private readonly string[] _bindings;
        private readonly TextBlock _status,_scaleValue,_opacityValue;
        private readonly ToggleButton _small,_medium,_current,_average,_computer;
        private readonly ToggleButton _themeAuto,_themeLight,_themeDark;
        private readonly CheckBox[] _sensors=new CheckBox[4];
        private readonly Expander _sensorChoices;
        private readonly Slider _scale,_opacity;
        private readonly Border _previewHost;
        private bool _syncing;
        private int _capturing=-1;
        private DispatcherOperation _fitOperation;
        internal bool Saved {get;private set;}
        internal TabControl Tabs {get;private set;}
        private readonly ScrollViewer[] _pages=new ScrollViewer[3];
        internal ScrollViewer Body {get{return _pages[Math.Max(0,Tabs.SelectedIndex)];}}
        internal string ScopeText {get{return _overlay.General?"Padrão para novos jogos":"Preferências para "+_overlay.GameName;}}
        internal string GameIdentity {get{return _overlay.GameIdentity;}}
        internal void AttachLiveOverlay(BenchmarkOverlay live){_session.Attach(live);}
        internal void SelectTab(int index){Tabs.SelectedIndex=index;UpdateLayout();}
        internal FrameworkElement PreviewPanel {get;private set;}
        internal Button SaveButton {get;private set;}
        internal Button CancelButton {get;private set;}
        internal Button ResetButton {get;private set;}
        internal Slider ScaleControl {get{return _scale;}}
        internal Slider OpacityControl {get{return _opacity;}}
        internal string ScaleText {get{return _scaleValue.Text;}}
        internal string OpacityText {get{return _opacityValue.Text;}}
        internal string ErrorText(int index){return _errors[index].Text;}
        internal Button KeyControl(int index){return _keys[index];}
        internal string Binding(int index){return _bindings[index];}
        internal string PreviewMetricText(int index){return _preview.MetricText(index);}
        private Brush Color(string hex){return _overlay.ThemeBrush(hex);}
        private const string Styles=@"<ResourceDictionary xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'>
<Style TargetType='Button'><Setter Property='Height' Value='34'/><Setter Property='Padding' Value='10,0'/><Setter Property='FontSize' Value='12'/><Setter Property='Foreground' Value='#F5F5F5'/><Setter Property='Background' Value='#1D2327'/><Setter Property='BorderBrush' Value='#424B52'/><Setter Property='Cursor' Value='Hand'/><Setter Property='Template'><Setter.Value><ControlTemplate TargetType='Button'><Border x:Name='edge' CornerRadius='5' Background='{TemplateBinding Background}' BorderBrush='{TemplateBinding BorderBrush}' BorderThickness='1' Padding='{TemplateBinding Padding}'><ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/></Border><ControlTemplate.Triggers><Trigger Property='IsMouseOver' Value='True'><Setter TargetName='edge' Property='BorderBrush' Value='#FF8000'/></Trigger><Trigger Property='IsKeyboardFocused' Value='True'><Setter TargetName='edge' Property='BorderBrush' Value='#FFAA4D'/><Setter TargetName='edge' Property='BorderThickness' Value='2'/></Trigger><Trigger Property='IsEnabled' Value='False'><Setter TargetName='edge' Property='Opacity' Value='.45'/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
<Style TargetType='ToggleButton'><Setter Property='Height' Value='34'/><Setter Property='Padding' Value='14,0'/><Setter Property='Foreground' Value='#E5E7EB'/><Setter Property='Background' Value='#1D2327'/><Setter Property='FontSize' Value='12'/><Setter Property='Template'><Setter.Value><ControlTemplate TargetType='ToggleButton'><Border x:Name='edge' Background='{TemplateBinding Background}' BorderBrush='#424B52' BorderThickness='1' CornerRadius='5' Padding='{TemplateBinding Padding}'><ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/></Border><ControlTemplate.Triggers><Trigger Property='IsChecked' Value='True'><Setter TargetName='edge' Property='Background' Value='#FF8000'/><Setter Property='Foreground' Value='#080808'/><Setter Property='FontWeight' Value='SemiBold'/></Trigger><Trigger Property='IsMouseOver' Value='True'><Setter TargetName='edge' Property='BorderBrush' Value='#FFAA4D'/></Trigger><Trigger Property='IsKeyboardFocused' Value='True'><Setter TargetName='edge' Property='BorderBrush' Value='#FFAA4D'/><Setter TargetName='edge' Property='BorderThickness' Value='2'/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
<Style x:Key='ComputerSwitch' TargetType='ToggleButton'><Setter Property='Height' Value='38'/><Setter Property='Foreground' Value='#F5F5F5'/><Setter Property='FontSize' Value='12'/><Setter Property='Template'><Setter.Value><ControlTemplate TargetType='ToggleButton'><Border x:Name='focus' BorderBrush='Transparent' BorderThickness='1' Padding='3' CornerRadius='4'><Grid><Grid.ColumnDefinitions><ColumnDefinition Width='44'/><ColumnDefinition/></Grid.ColumnDefinitions><Border x:Name='track' Height='22' Width='40' CornerRadius='11' Background='#424B52' HorizontalAlignment='Left'><Ellipse x:Name='thumb' Width='16' Height='16' Margin='3' Fill='White' HorizontalAlignment='Left'/></Border><ContentPresenter Grid.Column='1' Margin='8,0,0,0' VerticalAlignment='Center'/></Grid></Border><ControlTemplate.Triggers><Trigger Property='IsChecked' Value='True'><Setter TargetName='track' Property='Background' Value='#FF8000'/><Setter TargetName='thumb' Property='HorizontalAlignment' Value='Right'/></Trigger><Trigger Property='IsKeyboardFocused' Value='True'><Setter TargetName='focus' Property='BorderBrush' Value='#FFAA4D'/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
<Style TargetType='CheckBox'><Setter Property='Foreground' Value='#F5F5F5'/><Setter Property='MinHeight' Value='32'/><Setter Property='Template'><Setter.Value><ControlTemplate TargetType='CheckBox'><Border x:Name='focus' BorderBrush='Transparent' BorderThickness='1' CornerRadius='4' Padding='2'><StackPanel Orientation='Horizontal'><Border x:Name='check' Width='17' Height='17' CornerRadius='3' BorderBrush='#69757E' BorderThickness='1' Background='#161B1F' VerticalAlignment='Center'><TextBlock x:Name='mark' Text='✓' FontSize='13' Foreground='#080808' HorizontalAlignment='Center' Visibility='Collapsed'/></Border><ContentPresenter Margin='8,0,0,0' VerticalAlignment='Center'/></StackPanel></Border><ControlTemplate.Triggers><Trigger Property='IsChecked' Value='True'><Setter TargetName='check' Property='Background' Value='#FF8000'/><Setter TargetName='mark' Property='Visibility' Value='Visible'/></Trigger><Trigger Property='IsKeyboardFocused' Value='True'><Setter TargetName='focus' Property='BorderBrush' Value='#FFAA4D'/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
<Style x:Key='ExpanderHeader' TargetType='ToggleButton'><Setter Property='Foreground' Value='#D4D8DC'/><Setter Property='Height' Value='32'/><Setter Property='Template'><Setter.Value><ControlTemplate TargetType='ToggleButton'><Border x:Name='focus' BorderBrush='Transparent' BorderThickness='1' CornerRadius='4'><StackPanel Orientation='Horizontal'><TextBlock x:Name='arrow' Text='›' Foreground='#FFAA4D' Width='22' FontSize='18' VerticalAlignment='Center'/><ContentPresenter VerticalAlignment='Center'/></StackPanel></Border><ControlTemplate.Triggers><Trigger Property='IsChecked' Value='True'><Setter TargetName='arrow' Property='Text' Value='⌄'/></Trigger><Trigger Property='IsKeyboardFocused' Value='True'><Setter TargetName='focus' Property='BorderBrush' Value='#FFAA4D'/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
<Style TargetType='Expander'><Setter Property='Foreground' Value='#D4D8DC'/><Setter Property='FontSize' Value='12'/><Setter Property='Margin' Value='0,10,0,0'/><Setter Property='Template'><Setter.Value><ControlTemplate TargetType='Expander'><StackPanel><ToggleButton Style='{StaticResource ExpanderHeader}' Content='{TemplateBinding Header}' IsChecked='{Binding IsExpanded,RelativeSource={RelativeSource TemplatedParent},Mode=TwoWay}'/><ContentPresenter x:Name='body' Visibility='Collapsed' Margin='2,4,0,0'/></StackPanel><ControlTemplate.Triggers><Trigger Property='IsExpanded' Value='True'><Setter TargetName='body' Property='Visibility' Value='Visible'/></Trigger><Trigger Property='IsEnabled' Value='False'><Setter Property='Opacity' Value='.45'/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
<Style TargetType='Slider'><Setter Property='Height' Value='32'/><Setter Property='Template'><Setter.Value><ControlTemplate TargetType='Slider'><Grid><Border Height='4' Background='#424B52' CornerRadius='2' VerticalAlignment='Center'/><Track x:Name='PART_Track' Minimum='{TemplateBinding Minimum}' Maximum='{TemplateBinding Maximum}' Value='{TemplateBinding Value}'><Track.DecreaseRepeatButton><RepeatButton Command='Slider.DecreaseLarge'><RepeatButton.Template><ControlTemplate><Border Height='4' Background='#FF8000'/></ControlTemplate></RepeatButton.Template></RepeatButton></Track.DecreaseRepeatButton><Track.IncreaseRepeatButton><RepeatButton Command='Slider.IncreaseLarge'><RepeatButton.Template><ControlTemplate><Border Background='Transparent'/></ControlTemplate></RepeatButton.Template></RepeatButton></Track.IncreaseRepeatButton><Track.Thumb><Thumb Width='16' Height='22'><Thumb.Template><ControlTemplate><Border x:Name='knob' Background='#FF8000' BorderBrush='#FFB25C' BorderThickness='1' CornerRadius='5'/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb></Track><Border x:Name='focus' BorderBrush='Transparent' BorderThickness='1' CornerRadius='5' IsHitTestVisible='False'/></Grid><ControlTemplate.Triggers><Trigger Property='IsKeyboardFocusWithin' Value='True'><Setter TargetName='focus' Property='BorderBrush' Value='#FFAA4D'/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
<Style TargetType='ScrollBar'><Setter Property='Width' Value='10'/><Setter Property='Template'><Setter.Value><ControlTemplate TargetType='ScrollBar'><Track x:Name='PART_Track' Orientation='Vertical' IsDirectionReversed='True' Minimum='{TemplateBinding Minimum}' Maximum='{TemplateBinding Maximum}' Value='{TemplateBinding Value}' ViewportSize='{TemplateBinding ViewportSize}'><Track.Thumb><Thumb><Thumb.Template><ControlTemplate><Border Background='#535E66' CornerRadius='4' Margin='2,0'/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb></Track></ControlTemplate></Setter.Value></Setter></Style>
<Style TargetType='ToolTip'><Setter Property='Background' Value='#161B1F'/><Setter Property='Foreground' Value='#F5F5F5'/><Setter Property='MaxWidth' Value='340'/><Setter Property='ContentTemplate'><Setter.Value><DataTemplate><TextBlock Text='{Binding}' TextWrapping='Wrap'/></DataTemplate></Setter.Value></Setter></Style>
<Style TargetType='TabItem'><Setter Property='Foreground' Value='#D4D8DC'/><Setter Property='FontSize' Value='13'/><Setter Property='Template'><Setter.Value><ControlTemplate TargetType='TabItem'><Border x:Name='tab' Background='#171C20' BorderBrush='#424B52' BorderThickness='0,0,0,2' Padding='20,10' Margin='0,0,4,0' CornerRadius='5,5,0,0'><ContentPresenter ContentSource='Header'/></Border><ControlTemplate.Triggers><Trigger Property='IsSelected' Value='True'><Setter TargetName='tab' Property='BorderBrush' Value='#FF8000'/><Setter Property='Foreground' Value='#FFAA4D'/></Trigger><Trigger Property='IsKeyboardFocusWithin' Value='True'><Setter TargetName='tab' Property='Background' Value='#323A40'/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
<Style TargetType='TabControl'><Setter Property='Template'><Setter.Value><ControlTemplate TargetType='TabControl'><Grid><Grid.RowDefinitions><RowDefinition Height='Auto'/><RowDefinition/></Grid.RowDefinitions><TabPanel IsItemsHost='True' Margin='20,0,14,8'/><ContentPresenter x:Name='PART_SelectedContentHost' Grid.Row='1' ContentSource='SelectedContent'/></Grid></ControlTemplate></Setter.Value></Setter></Style>
</ResourceDictionary>";
        internal BenchmarkSettingsWindow(BenchmarkOverlay overlay,BenchmarkHotkeys hotkeys)
        {
            _overlay=overlay;_hotkeys=hotkeys;_session=new BenchmarkSettingsSession(overlay,hotkeys);
            _bindings=overlay.Preferences.Hotkeys==null?(hotkeys==null?new[]{"","",""}:hotkeys.Bindings):(string[])overlay.Preferences.Hotkeys.Clone();
            Title="Configurar overlay";Width=660;Height=780;MinWidth=480;MinHeight=320;WindowStartupLocation=WindowStartupLocation.CenterOwner;
            WindowStyle=WindowStyle.None;ResizeMode=ResizeMode.CanResize;ShowInTaskbar=false;FontFamily=new FontFamily("Segoe UI");FontSize=12;Foreground=Color("#F5F5F5");Background=Color("#080808");UseLayoutRounding=true;SnapsToDevicePixels=true;
            // Dynamic resources also update template parts, checked states and popups.
            string styles=Styles.Replace("Value='#080808'","Value='Black'").Replace("Foreground='#080808'","Foreground='Black'");
            styles=Regex.Replace(styles,"#[0-9A-Fa-f]{6}",delegate(Match match){return "{DynamicResource OverlayBrush_"+match.Value.Substring(1)+"}";});
            Resources=(ResourceDictionary)XamlReader.Parse(styles);
            foreach(Match match in Regex.Matches(Styles,"#[0-9A-Fa-f]{6}"))Resources["OverlayBrush_"+match.Value.Substring(1)]=Color(match.Value);
            WindowChrome.SetWindowChrome(this,new WindowChrome {CaptionHeight=72,ResizeBorderThickness=new Thickness(6),CornerRadius=new CornerRadius(12),GlassFrameThickness=new Thickness(0),UseAeroCaptionButtons=false});
            var grid=new Grid();grid.RowDefinitions.Add(new RowDefinition {Height=new GridLength(76)});grid.RowDefinitions.Add(new RowDefinition());grid.RowDefinitions.Add(new RowDefinition {Height=GridLength.Auto});
            Content=new Border {Background=Background,BorderBrush=Color("#FF8000"),BorderThickness=new Thickness(1.5),CornerRadius=new CornerRadius(12),Child=grid};
            var header=new Grid {Margin=new Thickness(20,8,14,8)};header.ColumnDefinitions.Add(new ColumnDefinition());header.ColumnDefinitions.Add(new ColumnDefinition {Width=new GridLength(42)});grid.Children.Add(header);
            var heading=new StackPanel {VerticalAlignment=VerticalAlignment.Center};heading.Children.Add(new TextBlock {Text=Title,FontSize=19,FontWeight=FontWeights.SemiBold});heading.Children.Add(new TextBlock {Text=ScopeText,Foreground=Color("#A9AFB8"),Margin=new Thickness(0,4,0,0),TextTrimming=TextTrimming.CharacterEllipsis});header.Children.Add(heading);
            var close=new Button {Name="SettingsClose",Content="✕",Width=38,Height=32,ToolTip="Fechar e descartar alterações não salvas"};Grid.SetColumn(close,1);WindowChrome.SetIsHitTestVisibleInChrome(close,true);header.Children.Add(close);close.Click+=delegate{Close();};
            Tabs=new TabControl {Name="SettingsTabs"};Grid.SetRow(Tabs,1);grid.Children.Add(Tabs);
            var appearance=TabPage(0,"Aparência");
            var themeRow=Row(appearance,"Tema:");_themeAuto=ThemeChoice(themeRow,"Automático","SettingsThemeAuto");_themeLight=ThemeChoice(themeRow,"Claro","SettingsThemeLight");_themeDark=ThemeChoice(themeRow,"Escuro","SettingsThemeDark");
            themeRow.ToolTip="Automático acompanha o Windows. Salvar mantém a escolha; Cancelar restaura a anterior.";
            _themeAuto.Click+=delegate{ChooseTheme("auto");};_themeLight.Click+=delegate{ChooseTheme("light");};_themeDark.Click+=delegate{ChooseTheme("dark");};
            _themeAuto.Checked+=delegate{if(!_syncing)ChooseTheme("auto");};_themeLight.Checked+=delegate{if(!_syncing)ChooseTheme("light");};_themeDark.Checked+=delegate{if(!_syncing)ChooseTheme("dark");};
            AutomationProperties.SetName(_themeAuto,"Tema automático — acompanhar o Windows");AutomationProperties.SetName(_themeLight,"Tema claro");AutomationProperties.SetName(_themeDark,"Tema escuro");
            appearance.Children.Add(Label("Prévia — valores ilustrativos",11,"#A9AFB8"));
            _preview=overlay.CreateIllustrativePreview();PreviewPanel=_preview.DetachPreviewContent();
            PreviewPanel.HorizontalAlignment=HorizontalAlignment.Center;
            _previewHost=new Border {Background=Color("#111619"),CornerRadius=new CornerRadius(6),Padding=new Thickness(12),Margin=new Thickness(0,8,0,12),Child=PreviewPanel,ToolTip="Prévia proporcional: a escala escolhida altera o tamanho dos textos e do painel. Valores ilustrativos."};
            _previewHost.SizeChanged+=delegate{ScalePreview();};appearance.Children.Add(_previewHost);
            var sizeRow=Row(appearance,"Tamanho:");_small=Choice(sizeRow,"Pequeno","SettingsSmall");_medium=Choice(sizeRow,"Médio","SettingsMedium");
            _small.Click+=delegate{Change(p=>p.Medium=false);};_medium.Click+=delegate{Change(p=>p.Medium=true);};
            _scale=SliderRow(appearance,"Escala",.75,1.75,out _scaleValue,"SettingsScale");_opacity=SliderRow(appearance,"Fundo",.35,1,out _opacityValue,"SettingsOpacity");
            appearance.Children.Add(Label("Mais transparente ↔ Mais opaco",11,"#A9AFB8"));appearance.Children.Add(Label("As mudanças aparecem imediatamente no overlay.",11,"#A9AFB8",new Thickness(0,10,0,0)));
            _scale.ValueChanged+=delegate{if(!_syncing)Change(p=>p.PanelScale=_scale.Value);};_opacity.ValueChanged+=delegate{if(!_syncing)Change(p=>p.BackgroundOpacity=_opacity.Value);};
            var information=TabPage(1,"Informações");var fpsRow=Row(information,"Indicador de FPS:");_current=Choice(fpsRow,"Atual","SettingsCurrentFps");_average=Choice(fpsRow,"Médio","SettingsAverageFps");fpsRow.ToolTip="Atual reage à janela de até 1 s. Médio usa a janela móvel de até 5 s, limitada a 4096 quadros.";
            information.Children.Add(Label("Atual reage às mudanças recentes; Médio resume a janela móvel.\n1% low: FPS calculado pela média do 1% de intervalos mais lentos.\nP99: 99% dos intervalos ficam abaixo desse tempo em ms.",11,"#A9AFB8",new Thickness(0,4,0,12)));
            _current.Click+=delegate{Change(p=>p.CurrentFps=true);};_average.Click+=delegate{Change(p=>p.CurrentFps=false);};
            _computer=new ToggleButton {Name="SettingsComputer",Content="Mostrar informações do computador",Style=(Style)Resources["ComputerSwitch"],Margin=new Thickness(0,8,0,0),HorizontalContentAlignment=HorizontalAlignment.Left};information.Children.Add(_computer);_computer.Click+=delegate{Change(p=>p.Sensors=_computer.IsChecked==true);};
            var sensorPanel=new WrapPanel();string[] names={"CPU","GPU","VRAM","RAM"};for(int i=0;i<4;i++){int index=i;_sensors[i]=new CheckBox {Name="SettingsSensor"+names[i],Content=names[i],Width=112,ToolTip="Leituras ausentes aparecem como Indisponível."};sensorPanel.Children.Add(_sensors[i]);_sensors[i].Click+=delegate{Change(p=>{bool enabled=_sensors[index].IsChecked==true;if(index==0)p.ShowCpu=enabled;else if(index==1)p.ShowGpu=enabled;else if(index==2)p.ShowVram=enabled;else p.ShowRam=enabled;});};}
            _sensorChoices=new Expander {Header="Escolher informações",Content=sensorPanel};information.Children.Add(_sensorChoices);
            information.Children.Add(Label("As quatro métricas do jogo permanecem sempre visíveis.",11,"#A9AFB8",new Thickness(0,8,0,0)));
            information.Children.Add(Label("Gráfico: posição relativa das amostras (0–100%), sem sincronização temporal entre capturas. Acima de 360 amostras, cada faixa mostra seu maior tempo para preservar picos. O botão Ref. oculta a curva sem apagar a referência.",11,"#A9AFB8",new Thickness(0,12,0,0)));
            information.Children.Add(new Expander {Header="Sobre as leituras",Content=Label("Indisponível significa que não há uma leitura confiável neste momento. Uso de CPU, GPU e RAM refere-se ao computador. VRAM mostra o adaptador com maior uso de memória dedicada. Temperaturas dependem de um provedor compatível já disponível. Leituras são atualizadas a cada cinco segundos.",11,"#A9AFB8")});
            var shortcuts=TabPage(2,"Atalhos");shortcuts.Children.Add(Label("Selecione um campo e pressione a combinação. Use Limpar para desativar.",11,"#A9AFB8"));
            string[] actions={"Mostrar/ocultar overlay","Iniciar/cancelar benchmark","Mover/travar overlay"};
            for(int i=0;i<3;i++){
                int index=i;shortcuts.Children.Add(Label(actions[i],12,"#F5F5F5",new Thickness(0,12,0,6)));var row=new Grid();row.ColumnDefinitions.Add(new ColumnDefinition());row.ColumnDefinitions.Add(new ColumnDefinition {Width=new GridLength(72)});shortcuts.Children.Add(row);
                _keys[i]=new Button {Name="SettingsHotkey"+i,HorizontalContentAlignment=HorizontalAlignment.Left,ToolTip="Ctrl, Alt ou Shift + letra ou F1–F24, exceto F12. Escape cancela a captura da tecla."};row.Children.Add(_keys[i]);_keys[i].Click+=delegate{BeginCapture(index);};
                _keys[i].LostKeyboardFocus+=delegate{if(_capturing==index)EndCapture();};
                _keys[i].PreviewKeyDown+=delegate(object sender,KeyEventArgs e){if(_capturing!=index)return;e.Handled=true;Key key=e.Key==Key.System?e.SystemKey:e.Key;if(key==Key.Escape){EndCapture();return;}if(key==Key.Back || key==Key.Delete){SetBinding(index,"");return;}if(key==Key.LeftCtrl||key==Key.RightCtrl||key==Key.LeftAlt||key==Key.RightAlt||key==Key.LeftShift||key==Key.RightShift)return;CaptureKey(index,key,Keyboard.Modifiers);};
                var clear=new Button {Name="SettingsClearHotkey"+i,Content="Limpar",Margin=new Thickness(8,0,0,0)};Grid.SetColumn(clear,1);row.Children.Add(clear);clear.Click+=delegate{SetBinding(index,"");};
                _errors[i]=Label("",11,"#FFB25C",new Thickness(0,4,0,0));shortcuts.Children.Add(_errors[i]);
            }
            var footer=new StackPanel {Margin=new Thickness(20,8,20,16)};Grid.SetRow(footer,2);grid.Children.Add(footer);_status=Label("",11,"#A9AFB8",new Thickness(0,0,0,8));_status.MinHeight=18;footer.Children.Add(_status);
            var footerButtons=new Grid();foreach(double weight in new[]{1.4,.8,2.0})footerButtons.ColumnDefinitions.Add(new ColumnDefinition {Width=new GridLength(weight,GridUnitType.Star)});footer.Children.Add(footerButtons);
            SaveButton=new Button {Name="SettingsSave",Content="Salvar alterações",Height=36,Background=Color("#FF8000"),Foreground=Brushes.Black,FontWeight=FontWeights.SemiBold};CancelButton=new Button {Name="SettingsCancel",Content="Cancelar",Height=36,Margin=new Thickness(8,0,0,0),IsCancel=true};ResetButton=new Button {Name="SettingsReset",Content="Restaurar padrão deste jogo",Height=36,Margin=new Thickness(8,0,0,0),FontSize=11};
            footerButtons.Children.Add(SaveButton);Grid.SetColumn(CancelButton,1);footerButtons.Children.Add(CancelButton);Grid.SetColumn(ResetButton,2);footerButtons.Children.Add(ResetButton);
            SaveButton.Click+=delegate{SaveChanges();};CancelButton.Click+=delegate{Close();};ResetButton.Click+=delegate{RestoreDefaults();};
            if(overlay.General)ResetButton.Content="Restaurar padrão geral";
            Closing+=delegate{_overlay.ThemeChanged-=RefreshTheme;_session.Dispose();_preview.Close();};
            Activated+=delegate{_session.SetFocused(true);};Deactivated+=delegate{EndCapture();_session.SetFocused(false);};
            Loaded+=delegate{FitWorkArea();};
            SourceInitialized+=delegate{var source=HwndSource.FromHwnd(new WindowInteropHelper(this).Handle);source.AddHook(DisplayHook);};
            if(hotkeys!=null)hotkeys.Capture=delegate(string value){if(_capturing>=0)SetBinding(_capturing,value);};
            Refresh();ValidateBindings();FitWorkArea();_overlay.ThemeChanged+=RefreshTheme;
        }
        private StackPanel TabPage(int index,string header)
        {
            var panel=new StackPanel();_pages[index]=new ScrollViewer {Name="SettingsPage"+index,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled,Padding=new Thickness(20,4,20,8),Content=panel};
            Tabs.Items.Add(new TabItem {Header=header,Content=_pages[index]});if(index==0)Tabs.SelectedIndex=0;return panel;
        }
        private TextBlock Label(string text,int size,string color,Thickness? margin=null){return new TextBlock {Text=text,FontSize=size,Foreground=Color(color),TextWrapping=TextWrapping.Wrap,Margin=margin??new Thickness(0)};}
        private StackPanel Section(StackPanel parent,string heading){var panel=new StackPanel();panel.Children.Add(Label(heading,17,"#F5F5F5",new Thickness(0,0,0,12)));parent.Children.Add(new Border {Background=Color("#0C0F10"),BorderBrush=Color("#30363B"),BorderThickness=new Thickness(1),CornerRadius=new CornerRadius(8),Padding=new Thickness(16),Margin=new Thickness(0,0,0,12),Child=panel});return panel;}
        private static StackPanel Row(StackPanel parent,string caption){var row=new StackPanel {Orientation=Orientation.Horizontal,Margin=new Thickness(0,4,0,8)};row.Children.Add(new TextBlock {Text=caption,Width=125,VerticalAlignment=VerticalAlignment.Center});parent.Children.Add(row);return row;}
        private static ToggleButton Choice(StackPanel parent,string text,string name){var button=new ToggleButton {Name=name,Content=text,Margin=new Thickness(0,0,6,0),MinWidth=76};parent.Children.Add(button);return button;}
        private ToggleButton ThemeChoice(StackPanel parent,string text,string name){var button=new RadioButton {Name=name,GroupName="OverlayTheme",Content=text,Style=(Style)Resources[typeof(ToggleButton)],Margin=new Thickness(0,0,6,0),MinWidth=76};parent.Children.Add(button);return button;}
        private Slider SliderRow(StackPanel parent,string text,double min,double max,out TextBlock value,string name){var row=new Grid {Margin=new Thickness(0,10,0,0)};row.ColumnDefinitions.Add(new ColumnDefinition());row.ColumnDefinitions.Add(new ColumnDefinition {Width=new GridLength(56)});row.Children.Add(Label(text,12,"#F5F5F5"));value=Label("",12,"#FFAA4D");value.HorizontalAlignment=HorizontalAlignment.Right;Grid.SetColumn(value,1);row.Children.Add(value);parent.Children.Add(row);var slider=new Slider {Name=name,Minimum=min,Maximum=max,TickFrequency=.05,SmallChange=.05,LargeChange=.1,IsSnapToTickEnabled=true};parent.Children.Add(slider);return slider;}
        private void ChooseTheme(string mode){_overlay.SetThemeMode(mode);RefreshTheme();}
        private void RefreshTheme(){if(_syncing)return;Refresh();_status.Text=_overlay.ThemeMode=="auto"?"Tema automático · acompanhando o Windows.":"Tema em prévia · salve para manter.";}
        private void Change(Action<BenchmarkOverlayPlacement> change){if(_syncing)return;_session.Apply(change);Refresh();_status.Text="Alterações em prévia · salve para manter.";}
        private void Refresh(){_syncing=true;var p=_overlay.Preferences;_themeAuto.IsChecked=p.ThemeMode=="auto";_themeLight.IsChecked=p.ThemeMode=="light";_themeDark.IsChecked=p.ThemeMode=="dark";_small.IsChecked=!p.Medium;_medium.IsChecked=p.Medium;_current.IsChecked=p.CurrentFps;_average.IsChecked=!p.CurrentFps;_scale.Value=p.PanelScale;_opacity.Value=p.BackgroundOpacity;_scaleValue.Text=Math.Round(p.PanelScale*100)+"%";_opacityValue.Text=Math.Round(p.BackgroundOpacity*100)+"%";_computer.IsChecked=p.Sensors;_sensorChoices.IsEnabled=p.Sensors;if(p.Sensors)_sensorChoices.IsExpanded=true;bool[] values={p.ShowCpu,p.ShowGpu,p.ShowVram,p.ShowRam};for(int i=0;i<4;i++)_sensors[i].IsChecked=values[i];_preview.Preferences.CopyFrom(p);_preview.ApplyPreferences(false);ScalePreview();RefreshKeys();_syncing=false;}
        private void ScalePreview()
        {
            if(_previewHost==null)return;
            double available=_previewHost.ActualWidth>24?_previewHost.ActualWidth-24:540;
            double factor=Math.Min(.75,available/(420*1.75))*_overlay.Preferences.PanelScale;
            if(Math.Abs(PreviewPanel.LayoutTransform.Value.M11-factor)>.0001)PreviewPanel.LayoutTransform=new ScaleTransform(factor,factor);
        }
        internal void BeginCapture(int index){SelectTab(2);EndCapture();_capturing=index;_keys[index].Content="Pressione a combinação";_keys[index].Focus();}
        private void EndCapture(){_capturing=-1;RefreshKeys();}
        private void RefreshKeys(){for(int i=0;i<3;i++)_keys[i].Content=i==_capturing?"Pressione a combinação":String.IsNullOrEmpty(_bindings[i])?"Não definido":_bindings[i];}
        internal void CaptureKey(int index,Key key,ModifierKeys modifiers){try{SetBinding(index,BenchmarkHotkeys.Combination(key,modifiers));}catch(ArgumentException ex){_errors[index].Text=ex.Message;}}
        internal void SetBinding(int index,string value){_bindings[index]=value;EndCapture();ValidateBindings();_status.Text="Alterações em prévia · salve para manter.";}
        private bool ValidateBindings(){uint[] mods=new uint[3],keys=new uint[3];bool valid=true;for(int i=0;i<3;i++){_errors[i].Text="";try{BenchmarkHotkeys.Parse(_bindings[i],out mods[i],out keys[i]);}catch(ArgumentException ex){_errors[i].Text=ex.Message;valid=false;}}for(int i=0;i<3;i++)for(int j=i+1;j<3;j++)if(keys[i]!=0&&keys[i]==keys[j]&&mods[i]==mods[j]){_errors[i].Text=_errors[j].Text="Esta combinação já está em outro comando.";valid=false;}return valid;}
        internal bool SaveChanges(){if(_capturing>=0){SelectTab(2);_errors[_capturing].Text="Conclua a combinação, use Limpar ou pressione Esc.";return false;}if(!ValidateBindings()){SelectTab(2);return false;}try{_session.Save(_bindings);Saved=true;Close();return true;}catch(BenchmarkHotkeyException ex){SelectTab(2);_errors[ex.Index].Text=ex.Message;return false;}catch(Exception){_status.Text="Não foi possível salvar este perfil. Verifique a pasta do Win-Slim. A prévia continua disponível.";return false;}}
        internal void RestoreDefaults(){Change(p=>{p.ThemeMode="auto";p.Medium=false;p.PanelScale=1;p.BackgroundOpacity=.93;p.CurrentFps=false;p.Sensors=false;p.ShowReference=true;p.ShowCpu=p.ShowGpu=p.ShowVram=p.ShowRam=true;});for(int i=0;i<3;i++)_bindings[i]="";EndCapture();ValidateBindings();}
        private void FitWorkArea()
        {
            double height=SystemParameters.WorkArea.Height-24,width=SystemParameters.WorkArea.Width-24;IntPtr handle=new WindowInteropHelper(this).Handle;
            double sx=1,sy=1;BenchmarkGameWindow.Bounds work=new BenchmarkGameWindow.Bounds();bool native=false;
            try{if(handle!=IntPtr.Zero){work=BenchmarkOverlayDesktop.WorkArea(handle);var source=PresentationSource.FromVisual(this);if(source!=null&&source.CompositionTarget!=null){sx=source.CompositionTarget.TransformToDevice.M11;sy=source.CompositionTarget.TransformToDevice.M22;}width=(work.Right-work.Left-24)/sx;height=(work.Bottom-work.Top-24)/sy;native=true;}}catch(System.IO.IOException){}
            MinHeight=Math.Min(320,Math.Max(160,height));MinWidth=Math.Min(480,Math.Max(240,width));MaxHeight=Math.Max(MinHeight,height);MaxWidth=Math.Max(MinWidth,width);Height=Math.Min(Height,MaxHeight);Width=Math.Min(Width,MaxWidth);
            if(native){var rect=BenchmarkOverlayDesktop.Rect(handle);int w=(int)Math.Ceiling(Width*sx),h=(int)Math.Ceiling(Height*sy);int left=Math.Max(work.Left,Math.Min(rect.Left,work.Right-w)),top=Math.Max(work.Top,Math.Min(rect.Top,work.Bottom-h));BenchmarkGameWindow.SetWindowPos(handle,IntPtr.Zero,left,top,w,h,0x14);}
        }
        private IntPtr DisplayHook(IntPtr hwnd,int message,IntPtr wp,IntPtr lp,ref bool handled){if((message==0x2E0||message==0x7E||message==0x232)&&(_fitOperation==null||_fitOperation.Status!=DispatcherOperationStatus.Pending))_fitOperation=Dispatcher.InvokeAsync((Action)FitWorkArea);return IntPtr.Zero;}
    }
}
